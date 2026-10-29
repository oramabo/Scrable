#!/usr/bin/env python3
"""Download the Mordo (pitaronfree.blogspot.com) clue dictionary through the Blogger feed API.

Writes one JSON file per feed page into OUT_DIR/pages/page_NNNN.json and never re-downloads a page that
is already present, so the run can be resumed. The feed is public and allowed by the site's robots.txt;
we fetch sequentially with a pause between requests to stay polite.

Usage: python3 -I scrape_mordo.py OUT_DIR [--max-results 150] [--delay 0.8]
"""
import argparse
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

FEED = "https://pitaronfree.blogspot.com/feeds/posts/default?alt=json&max-results={n}&start-index={start}"
UA = "ChetzContentBot/1.0 (+content pipeline for a crossword app; contact via GitHub oramabo/Scrable)"


def ssl_context() -> ssl.SSLContext:
    cafile = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
    for candidate in (cafile, "/root/.ccr/ca-bundle.crt"):
        if candidate and os.path.exists(candidate):
            return ssl.create_default_context(cafile=candidate)
    return ssl.create_default_context()


def fetch(url: str, ctx: ssl.SSLContext, retries: int = 6) -> dict:
    delay = 2.0
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            code = getattr(exc, "code", None)
            if code is not None and 400 <= code < 500 and code not in (429, 408):
                raise
            print(f"  retry {attempt + 1}/{retries} after error: {exc}", file=sys.stderr)
            time.sleep(delay)
            delay = min(delay * 2, 60)
    raise RuntimeError(f"gave up on {url}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--max-results", type=int, default=150)
    ap.add_argument("--delay", type=float, default=0.8)
    args = ap.parse_args()

    pages_dir = os.path.join(args.out_dir, "pages")
    os.makedirs(pages_dir, exist_ok=True)
    ctx = ssl_context()

    first = fetch(FEED.format(n=1, start=1), ctx)
    total = int(first["feed"]["openSearch$totalResults"]["$t"])
    n = args.max_results
    page_count = (total + n - 1) // n
    print(f"total posts: {total}; pages of {n}: {page_count}")

    entries_seen = 0
    for page in range(page_count):
        path = os.path.join(pages_dir, f"page_{page + 1:04d}.json")
        if os.path.exists(path):
            continue
        start = page * n + 1
        data = fetch(FEED.format(n=n, start=start), ctx)
        entries = data.get("feed", {}).get("entry", [])
        slim = []
        for e in entries:
            links = [l["href"] for l in e.get("link", []) if l.get("rel") == "alternate"]
            slim.append({
                "id": e.get("id", {}).get("$t"),
                "published": e.get("published", {}).get("$t"),
                "updated": e.get("updated", {}).get("$t"),
                "title": e.get("title", {}).get("$t"),
                "url": links[0] if links else None,
                "content": (e.get("content") or e.get("summary") or {}).get("$t", ""),
            })
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"start": start, "entries": slim}, fh, ensure_ascii=False)
        os.replace(tmp, path)
        entries_seen += len(slim)
        if (page + 1) % 20 == 0 or page + 1 == page_count:
            print(f"page {page + 1}/{page_count} ({entries_seen} entries this run)", flush=True)
        if not entries:
            print("empty page; stopping early", file=sys.stderr)
            break
        time.sleep(args.delay)
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
