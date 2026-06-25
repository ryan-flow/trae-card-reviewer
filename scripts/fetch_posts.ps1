# fetch_posts.ps1 - 增量爬取帖子详情 + 图片离线缓存
# 用法: powershell -ExecutionPolicy Bypass -File fetch_posts.ps1 [-Limit 5] [-Ids "39845,32905"]
param(
    [int]$Limit = 5,
    [string]$Ids = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dataDir = Join-Path $root "data"
$postsDir = Join-Path $dataDir "posts"
$imgDir = Join-Path $dataDir "images"
$topicsFile = Join-Path $dataDir "topics.json"
$csvFile = Join-Path $PWD "trae_topics.csv"

Write-Host "=== TRAE Posts Fetcher ==="
Write-Host "Root: $root"

# 用 .NET 显式 UTF-8 读 CSV（PS5 的 Import-Csv 默认 ANSI 会乱码）
if (-not (Test-Path $csvFile)) {
    Write-Host "CSV not found at $csvFile"
    exit 1
}
$csvText = [System.IO.File]::ReadAllText($csvFile, [System.Text.Encoding]::UTF8)
$allTopics = $csvText | ConvertFrom-Csv
Write-Host "Loaded $($allTopics.Count) topics from CSV"
Write-Host "Sample: [$($allTopics[0].Id)] $($allTopics[0].Title.Substring(0,[Math]::Min(40,$allTopics[0].Title.Length)))"

# 选目标
$targets = @()
if ($Ids) {
    $idList = $Ids -split "," | ForEach-Object { $_.Trim() }
    $targets = $allTopics | Where-Object { $idList -contains $_.Id }
} else {
    $targets = $allTopics | Where-Object { -not ([bool]::Parse($_.Pinned)) -and -not ([bool]::Parse($_.Deleted)) } |
        Sort-Object @{Expression={[int]$_.Votes};Descending=$true}, @{Expression={[int]$_.Views};Descending=$true} |
        Select-Object -First $Limit
}

Write-Host ""
Write-Host "Targets: $($targets.Count)"
foreach ($t in $targets) {
    $title = $t.Title
    if ($title.Length -gt 50) { $title = $title.Substring(0,50) + "..." }
    Write-Host ("  [{0}] {1} (votes={2})" -f $t.Id, $title, $t.Votes)
}
Write-Host ""

# 建目录
foreach ($d in @($postsDir, $imgDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# 加载已有索引
$topicsIndex = @{}
if (Test-Path $topicsFile) {
    $existing = [System.IO.File]::ReadAllText($topicsFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($t in $existing) { $topicsIndex[[int]$t.id] = $t }
}

$base = "https://forum.trae.cn"
$headers = @{ "Accept" = "application/json"; "User-Agent" = "Mozilla/5.0" }
$success = 0; $skipped = 0; $failed = 0

foreach ($t in $targets) {
    $id = $t.Id
    $outFile = Join-Path $postsDir "$id.json"

    if (Test-Path $outFile) {
        Write-Host "[$id] skip (exists)"
        $skipped++
        continue
    }

    try {
        $url = "$base/t/topic/$id.json"
        Write-Host "[$id] fetching..."
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop

        if ($null -eq $resp.post_stream -or $null -eq $resp.post_stream.posts -or $resp.post_stream.posts.Count -eq 0) {
            throw "post_stream empty"
        }

        $cooked = $resp.post_stream.posts[0].cooked
        Write-Host "  cooked len: $($cooked.Length)"

        # 提取并下载图片（避免用 $matches 自动变量名）
        $imgRegex = [regex]'src="(https?://[^"]+)"'
        $imgMatches = $imgRegex.Matches($cooked)
        $imgCount = 0
        foreach ($m in $imgMatches) {
            $imgUrl = $m.Groups[1].Value

            # 计算 hash 文件名
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($imgUrl))
            $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()

            # 推断扩展名
            $ext = ".png"
            if ($imgUrl -match '\.(jpg|jpeg|png|gif|webp|svg)') {
                $e = $Matches[1].ToLower()
                if ($e -eq "jpeg") { $e = "jpg" }
                $ext = ".$e"
            }

            $localName = "$hash$ext"
            $localPath = Join-Path $imgDir $localName
            $localUrl = "../images/$localName"

            if (-not (Test-Path $localPath)) {
                try {
                    Invoke-WebRequest -Uri $imgUrl -OutFile $localPath -UseBasicParsing -ErrorAction Stop -Headers $headers
                    $imgCount++
                } catch {
                    Write-Host "  img fail: $($_.Exception.Message)"
                    continue
                }
            }
            $cooked = $cooked.Replace($imgUrl, $localUrl)
        }

        # 构造详情
        $tags = @()
        if ($resp.tags) { foreach ($tg in $resp.tags) { $tags += $tg.name } }

        $detail = [PSCustomObject]@{
            id            = [int]$id
            title         = $resp.title
            fancy_title   = $resp.fancy_title
            tags          = $tags
            views         = [int]$resp.views
            like_count    = [int]$resp.like_count
            reply_count   = [int]$resp.reply_count
            vote_count    = [int]$resp.vote_count
            posts_count   = [int]$resp.posts_count
            created_at    = $resp.created_at
            last_posted_at = $resp.last_posted_at
            image_url     = $resp.image_url
            word_count    = [int]$resp.word_count
            cooked        = $cooked
            url           = "$base/t/topic/$id"
            fetched_at    = (Get-Date).ToString("o")
        }

        $detail | ConvertTo-Json -Depth 6 | Out-File -FilePath $outFile -Encoding UTF8
        Write-Host "  OK (imgs=$imgCount, words=$($detail.word_count))"
        $success++

        # 更新索引
        $topicsIndex[[int]$id] = [PSCustomObject]@{
            id         = [int]$id
            title      = $resp.title
            tags       = ($tags -join ",")
            votes      = [int]$resp.vote_count
            views      = [int]$resp.views
            replies    = [int]$resp.reply_count
            likes      = [int]$resp.like_count
            created    = ([datetime]$resp.created_at).ToString("MM-dd HH:mm")
            url        = "$base/t/topic/$id"
            has_detail = $true
        }

        Start-Sleep -Milliseconds 400
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)"
        $failed++
    }
}

# 保存索引（按 id 排序）
$indexArr = @($topicsIndex.Values | Sort-Object id)
$indexArr | ConvertTo-Json -Depth 4 | Out-File -FilePath $topicsFile -Encoding UTF8

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Success: $success  Skipped: $skipped  Failed: $failed"
Write-Host "Index: $topicsFile ($($indexArr.Count) entries)"
