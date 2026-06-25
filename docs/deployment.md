# 部署指南

## 方式一：IGA Pages（推荐，免费 + 全球 CDN）

1. **推送到 GitHub**
   ```bash
   git add . && git commit -m "init" && git push
   ```

2. **创建 IGA Pages 项目**
   - 访问 https://console.volcengine.com/dcdn/pages
   - 新建项目 → 选择 GitHub 仓库
   - 构建命令：留空（纯静态）
   - 输出目录：`/`

3. **自动部署**
   - 每次 `git push` 自动触发部署
   - 获得全球可访问的 `*.iga-pages.com` 链接

## 方式二：自有服务器（Nginx）

```bash
# Ubuntu 服务器
ssh root@106.55.55.54

# 克隆仓库
cd /var/www
git clone https://github.com/你的用户名/trae-card-reviewer.git

# Nginx 配置
cat > /etc/nginx/sites-available/trae-reviewer << 'EOF'
server {
    listen 80;
    server_name your-domain.com;
    root /var/www/trae-card-reviewer;
    index app/index.html;
    location / { try_files $uri $uri/ =404; }
}
EOF

ln -s /etc/nginx/sites-available/trae-reviewer /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

## 定时增量爬取（Ubuntu cron）

```bash
# 每天凌晨 3 点爬取新帖
crontab -e
0 3 * * * cd /var/www/trae-card-reviewer && python3 scripts/crawl.py posts --limit 20 && git add data/ && git commit -m "auto: crawl new posts" && git push
```
