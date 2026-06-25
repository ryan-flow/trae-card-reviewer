# run_reviewer.ps1 - 启动 HTTP 静态服务器（手机可访问）
# 用法: powershell -ExecutionPolicy Bypass -File run_reviewer.ps1
# 用 TcpListener 实现，不需要管理员权限，监听 0.0.0.0
param([int]$Port = 8000)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Resolve-Path (Join-Path $PSScriptRoot "")

# 取本机局域网 IPv4
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -eq 'Dhcp' } |
  Sort-Object InterfaceIndex | Select-Object -First 1).IPAddress
if (-not $lanIp) {
  $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1).IPAddress
}

Write-Host "=== TRAE Reviewer Server ===" -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host ""
Write-Host "Local URL:  http://localhost:$Port/" -ForegroundColor Green
if ($lanIp) {
  Write-Host "Phone URL:  http://${lanIp}:$Port/" -ForegroundColor Magenta
  Write-Host ""
  Write-Host "  手机和电脑必须连同一个 WiFi" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "Press Ctrl+C to stop"
Write-Host ""

# 检查防火墙
$fwRule = Get-NetFirewallRule -DisplayName "TRAE Reviewer*" -ErrorAction SilentlyContinue
if (-not $fwRule -and $lanIp) {
  Write-Host "[!] 防火墙未放行，手机可能无法访问。请右键管理员运行 setup_firewall.ps1 一次" -ForegroundColor Yellow
  Write-Host ""
}

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.webp' = 'image/webp'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
  '.txt'  = 'text/plain; charset=utf-8'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
}

# 用 TcpListener 监听所有网卡（无需管理员权限）
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
try {
  $listener.Start()
} catch {
  Write-Host "Failed to start: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Try another port: powershell -File run_reviewer.ps1 -Port 8080"
  exit 1
}

# 打开浏览器
Start-Process "http://localhost:$Port/"

# HTTP 响应辅助函数
function Send-Response($stream, $statusCode, $statusText, $bodyBytes, $contentType) {
  $header = "HTTP/1.1 $statusCode $statusText`r`n" +
            "Content-Type: $contentType`r`n" +
            "Content-Length: $($bodyBytes.Length)`r`n" +
            "Access-Control-Allow-Origin: *`r`n" +
            "Connection: close`r`n" +
            "Cache-Control: no-cache`r`n" +
            "`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  $stream.Write($bodyBytes, 0, $bodyBytes.Length)
  $stream.Flush()
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $client.ReceiveTimeout = 5000
      $stream = $client.GetStream()
      
      # 读 HTTP 请求头（循环读到 \r\n\r\n）
      $reqBuf = New-Object byte[] 16384
      $totalRead = 0
      $headerEnd = -1
      while ($totalRead -lt 16384) {
        $n = $stream.Read($reqBuf, $totalRead, 16384 - $totalRead)
        if ($n -le 0) { break }
        $totalRead += $n
        $reqStr = [System.Text.Encoding]::ASCII.GetString($reqBuf, 0, $totalRead)
        $headerEnd = $reqStr.IndexOf("`r`n`r`n")
        if ($headerEnd -ge 0) { break }
      }
      
      if ($totalRead -le 0) { continue }
      $reqStr = [System.Text.Encoding]::ASCII.GetString($reqBuf, 0, [Math]::Min($totalRead, 4096))
      $firstLine = ($reqStr -split "`r`n")[0]
      # GET /path HTTP/1.1
      $parts = $firstLine -split ' '
      if ($parts.Count -lt 2) { continue }
      $method = $parts[0]
      $rawPath = $parts[1]
      
      # URL 解码 + 去掉 query string
      $path = [System.Uri]::UnescapeDataString($rawPath.Split('?')[0])
      if ($path -eq "/" -or $path -eq "") { $path = "/app/index.html" }
      
      Write-Host "[$method] $path" -NoNewline
      
      # 安全：防止路径穿越
      $relPath = $path.TrimStart("/").Replace("/", "\")
      $fullPath = Join-Path $root $relPath
      
      try {
        $fullResolved = (Resolve-Path $fullPath -ErrorAction Stop).Path
        if (-not $fullResolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "path traversal blocked"
        }
        if (-not (Test-Path $fullResolved -PathType Leaf)) { throw "not a file" }
        
        $bytes = [System.IO.File]::ReadAllBytes($fullResolved)
        $ext = [System.IO.Path]::GetExtension($fullResolved).ToLower()
        $ct = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        Send-Response $stream 200 "OK" $bytes $ct
        $sizeKB = [Math]::Round($bytes.Length / 1024, 1)
        Write-Host ('  200 ' + $sizeKB + ' KB') -ForegroundColor Green
      } catch {
        $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $path")
        Send-Response $stream 404 "Not Found" $body "text/plain; charset=utf-8"
        Write-Host "  404" -ForegroundColor Yellow
      }
    } catch {
      # 连接异常，忽略
    } finally {
      try { $stream.Close() } catch {}
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
  Write-Host "`nServer stopped."
}
