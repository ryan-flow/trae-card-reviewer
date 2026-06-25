# TRAE Card Reviewer · 卡片审阅官

> TRAE 创意大赛评委专用 —— Tinder 式卡片浏览 + 评分系统

【学习工作赛道】TRAE Card Reviewer —— 让评委在手机上滑动审阅 1800+ 参赛作品

---

## 创意介绍

**想解决什么问题：** TRAE 创意大赛初赛有上千个参赛帖，评委需要在论坛里逐个点开、阅读正文、查看图片、对比打分。传统列表+翻页的浏览方式效率极低，移动端体验更差。

**为什么会想到做这个：** 作为大赛评委，我在手机上审阅帖子时发现：论坛的列表视图信息密度低、无法快速标记喜欢/不喜欢、评分记录散落无追踪。Tinder 式的"卡片左右滑"交互天然适合"快速决策"场景。

**大概是什么产品：** 一个移动端优先的 Web 应用，将参赛帖以卡片形式呈现，左滑不喜欢、右滑喜欢、上滑看正文详情，评分记录持久化在本地。

## 目标用户及痛点

**面向哪些用户：** TRAE 创意大赛评委、社区版主、需要批量审阅结构化内容的产品经理。

**在什么场景下使用：** 评委在通勤、碎片时间用手机刷参赛作品，快速标记倾向后再回到电脑细看高赞帖。

**当前痛点：** 没有产品时，评委只能用论坛网页逐个点开帖子，无法批量标记、无法离线浏览、无法统计已审阅进度。

## 价值与意义

- **效率提升：** 卡片浏览 + 手势操作让审阅速度提升 3-5 倍，Tinder 式交互降低决策疲劳
- **社会价值：** 降低评委参与门槛 = 大赛能吸引更多评委 = 更多创意作品被认真审阅

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 前端 | 原生 HTML + CSS + JS | 零构建、零依赖，单文件部署 |
| 设计 | Glassmorphism + Linear Design System | 毛玻璃质感 + 深色配色 |
| 数据 | Discourse JSON API → 静态 JSON | 论坛爬虫输出结构化数据 |
| 爬虫 | Python (requests) | 跨平台，Ubuntu cron 定时增量爬取 |
| 部署 | IGA Pages | 火山引擎免费静态托管 + 全球 CDN |
| 评分 | localStorage | 评委本机持久化，无需后端 |

## 项目结构

```
trae-card-reviewer/
├── app/
│   └── index.html          # 前端（单文件，含 CSS+JS）
├── data/
│   ├── topics.json         # 帖子列表（标题/标签/投票数）
│   └── posts/
│       └── {id}.json       # 帖子详情（正文 HTML + 元数据）
├── scripts/
│   ├── crawl.py            # Python 爬虫（跨平台）
│   ├── fetch_posts.ps1     # PowerShell 爬虫（Windows 版，含图片离线缓存）
│   └── serve.ps1           # 本地开发服务器
├── docs/
│   └── deployment.md       # 部署指南
├── .gitignore
└── README.md
```

## 快速开始

### 本地运行

```powershell
# 1. 启动本地服务器（PowerShell）
cd trae-card-reviewer
powershell -ExecutionPolicy Bypass -File scripts/serve.ps1

# 2. 浏览器打开 http://localhost:8080/app/
```

### 爬取数据

```bash
# Python 爬虫（推荐，跨平台）
pip install requests

# 爬取话题列表
python scripts/crawl.py topics --pages 5

# 爬取帖子详情（增量）
python scripts/crawl.py posts --limit 10

# 指定帖子 ID 重爬
python scripts/crawl.py posts --ids 39845,32905 --force
```

### 部署到 IGA Pages

1. 将本仓库推送到 GitHub
2. 在 [IGA Pages 控制台](https://console.volcengine.com/dcdn/pages) 创建项目，选择 GitHub 仓库
3. 构建命令留空（纯静态），输出目录填 `/`
4. git push 后自动部署，获得全球可访问的链接

详见 [docs/deployment.md](docs/deployment.md)

## 交互手势

| 手势 | 动作 |
|---|---|
| ← 左滑 | 不喜欢 (NOPE) |
| → 右滑 | 喜欢 (LIKE) |
| ↑ 上滑 | 查看正文详情 |
| ↓ 下滑 | 收起详情 / 跳过 |
| 键盘 ← | 不喜欢 |
| 键盘 → | 喜欢 |
| 键盘 ↑ | 详情 |
| Space | 跳过 |
| S | 评分 |

## 设计亮点

- **Glassmorphism 毛玻璃：** header/footer/卡片均使用 backdrop-filter 实现真实毛玻璃效果
- **Linear 配色：** 灵感来自 Linear app，靛蓝主色 + zinc 深色背景，对比度达 AA 16.9:1
- **三层卡片堆叠：** 当前卡片 + 2 张缩放偏移的背景卡片，营造纵深感
- **移动优先：** 安全区适配、触摸手势优化、passive 事件处理

## License

MIT
