#!/usr/bin/env python3
"""
TRAE Card Reviewer - 跨平台爬虫
爬取 TRAE 论坛帖子列表 + 详情，输出 JSON 供前端使用。

用法:
  python crawl.py topics [--pages 5]          # 爬取话题列表
  python crawl.py posts  [--limit 5] [--ids 39845,32905]  # 爬取帖子详情
  python crawl.py all    [--limit 5]          # 话题 + 详情一起爬

依赖: requests (pip install requests)
"""
import argparse
import json
import os
import sys
import time
import hashlib
from pathlib import Path
from datetime import datetime

try:
    import requests
except ImportError:
    print("缺少 requests 库，请运行: pip install requests")
    sys.exit(1)

BASE = "https://forum.trae.cn"
HEADERS = {
    "Accept": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
}

# 项目根目录 (scripts/ 的上一级)
ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
POSTS_DIR = DATA_DIR / "posts"
IMG_DIR = DATA_DIR / "images"
TOPICS_FILE = DATA_DIR / "topics.json"


def ensure_dirs():
    """创建必要目录"""
    for d in [DATA_DIR, POSTS_DIR, IMG_DIR]:
        d.mkdir(parents=True, exist_ok=True)


def fetch_topics(pages=5):
    """爬取话题列表"""
    ensure_dirs()
    all_topics = []
    seen_ids = set()

    for page in range(pages):
        url = f"{BASE}/c/38-category/40-category/40.json"
        params = {"page": page}
        print(f"[topics] page {page}...")
        try:
            resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            print(f"  fail: {e}")
            break

        topics = data.get("topic_list", {}).get("topics", [])
        if not topics:
            print("  no more topics")
            break

        for t in topics:
            tid = t.get("id")
            if tid in seen_ids:
                continue
            seen_ids.add(tid)
            tags = [tag.get("name", "") for tag in t.get("tags", []) or []]
            all_topics.append({
                "id": tid,
                "title": t.get("title", ""),
                "tags": tags,
                "votes": t.get("vote_count", 0),
                "views": t.get("views", 0),
                "replies": t.get("posts_count", 0) - 1 if t.get("posts_count", 0) > 0 else 0,
                "pinned": t.get("pinned", False),
                "created_at": t.get("created_at", ""),
                "last_posted_at": t.get("last_posted_at", ""),
            })

        time.sleep(0.5)  # 限流

    # 按 votes 降序
    all_topics.sort(key=lambda x: x.get("votes", 0), reverse=True)

    with open(TOPICS_FILE, "w", encoding="utf-8") as f:
        json.dump(all_topics, f, ensure_ascii=False, indent=2)

    print(f"\n[topics] done: {len(all_topics)} topics -> {TOPICS_FILE}")
    return all_topics


def load_topics():
    """加载已有 topics.json"""
    if not TOPICS_FILE.exists():
        print(f"topics.json not found at {TOPICS_FILE}")
        return []
    with open(TOPICS_FILE, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def download_image(url, force=False):
    """下载图片到本地，返回本地相对路径。失败返回 None。"""
    md5 = hashlib.md5(url.encode("utf-8")).hexdigest()
    ext = ".png"
    for e in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"]:
        if e in url.lower():
            ext = ".jpg" if e == ".jpeg" else e
            break
    local_name = f"{md5}{ext}"
    local_path = IMG_DIR / local_name

    if local_path.exists() and not force:
        return f"../images/{local_name}"

    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
        with open(local_path, "wb") as f:
            f.write(resp.content)
        return f"../images/{local_name}"
    except Exception as e:
        print(f"  img fail: {e}")
        return None


def fetch_post_detail(topic_id, cache_images=False):
    """爬取单个帖子详情"""
    url = f"{BASE}/t/topic/{topic_id}.json"
    print(f"[{topic_id}] fetching...")
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        print(f"  fail: {e}")
        return None

    post_stream = data.get("post_stream", {})
    posts = post_stream.get("posts", [])
    if not posts:
        print(f"  empty post_stream")
        return None

    cooked_remote = posts[0].get("cooked", "")
    cooked_local = cooked_remote

    # 可选：下载图片并替换为本地路径
    if cache_images:
        import re
        img_urls = re.findall(r'src="(https?://[^"]+)"', cooked_remote)
        img_count = 0
        for img_url in img_urls:
            local_path = download_image(img_url)
            if local_path:
                cooked_local = cooked_local.replace(img_url, local_path)
                img_count += 1
        print(f"  cached {img_count} images")

    tags = [tag.get("name", "") for tag in data.get("tags", []) or []]

    detail = {
        "id": topic_id,
        "title": data.get("title", ""),
        "fancy_title": data.get("fancy_title", ""),
        "tags": tags,
        "views": data.get("views", 0),
        "like_count": data.get("like_count", 0),
        "reply_count": data.get("reply_count", 0),
        "vote_count": data.get("vote_count", 0),
        "posts_count": data.get("posts_count", 0),
        "created_at": data.get("created_at", ""),
        "last_posted_at": data.get("last_posted_at", ""),
        "image_url": data.get("image_url", ""),
        "word_count": len(cooked_remote),
        "cooked_remote": cooked_remote,
        "cooked_local": cooked_local,
        "url": f"{BASE}/t/topic/{topic_id}",
        "fetched_at": datetime.now().isoformat(),
    }

    out_file = POSTS_DIR / f"{topic_id}.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(detail, f, ensure_ascii=False, indent=2)

    print(f"  OK (votes={detail['vote_count']}, words={detail['word_count']})")
    return detail


def fetch_posts(limit=5, ids=None, cache_images=False):
    """爬取帖子详情（增量）"""
    ensure_dirs()
    topics = load_topics()
    if not topics:
        print("No topics found. Run 'python crawl.py topics' first.")
        return

    # 选择目标
    if ids:
        id_list = [int(x.strip()) for x in ids.split(",")]
        targets = [t for t in topics if t["id"] in id_list]
    else:
        targets = [t for t in topics if not t.get("pinned")]  # 跳过置顶
        targets.sort(key=lambda x: x.get("votes", 0), reverse=True)
        targets = targets[:limit]

    print(f"\nTargets: {len(targets)}")
    for t in targets:
        title = t["title"][:50] + "..." if len(t["title"]) > 50 else t["title"]
        print(f"  [{t['id']}] {title} (votes={t.get('votes', 0)})")

    success, skipped, failed = 0, 0, 0
    for t in targets:
        tid = t["id"]
        out_file = POSTS_DIR / f"{tid}.json"

        # 增量：已存在则跳过（除非 --force）
        if out_file.exists() and not ids:
            print(f"[{tid}] skip (exists)")
            skipped += 1
            continue

        result = fetch_post_detail(tid, cache_images=cache_images)
        if result:
            success += 1
        else:
            failed += 1

        time.sleep(0.8)  # 限流

    print(f"\n[posts] done: success={success}, skipped={skipped}, failed={failed}")
    print(f"  output: {POSTS_DIR}")


def main():
    parser = argparse.ArgumentParser(description="TRAE 论坛爬虫")
    sub = parser.add_subparsers(dest="command", help="子命令")

    p_topics = sub.add_parser("topics", help="爬取话题列表")
    p_topics.add_argument("--pages", type=int, default=5, help="爬取页数 (默认5)")

    p_posts = sub.add_parser("posts", help="爬取帖子详情")
    p_posts.add_argument("--limit", type=int, default=5, help="爬取数量 (默认5)")
    p_posts.add_argument("--ids", type=str, default="", help="指定帖子ID (逗号分隔)")
    p_posts.add_argument("--cache-images", action="store_true", help="下载图片到本地")
    p_posts.add_argument("--force", action="store_true", help="强制重爬已存在的帖子")

    p_all = sub.add_parser("all", help="话题 + 详情一起爬")
    p_all.add_argument("--pages", type=int, default=5, help="话题页数")
    p_all.add_argument("--limit", type=int, default=5, help="详情数量")
    p_all.add_argument("--cache-images", action="store_true", help="下载图片到本地")

    args = parser.parse_args()

    if args.command == "topics":
        fetch_topics(pages=args.pages)
    elif args.command == "posts":
        if args.force and args.ids:
            # --force + --ids: 重爬指定帖子
            ensure_dirs()
            topics = load_topics()
            id_list = [int(x.strip()) for x in args.ids.split(",")]
            targets = [t for t in topics if t["id"] in id_list]
            for t in targets:
                fetch_post_detail(t["id"], cache_images=args.cache_images)
                time.sleep(0.8)
        else:
            fetch_posts(limit=args.limit, ids=args.ids, cache_images=args.cache_images)
    elif args.command == "all":
        fetch_topics(pages=args.pages)
        fetch_posts(limit=args.limit, cache_images=args.cache_images)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
