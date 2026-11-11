#!/usr/bin/env python3
"""radio-meta.py URL THUMB_DIR  ->  prints one JSON line {"title": ..., "thumb": ...}"""
import hashlib, json, os, re, shutil, subprocess, sys
from html import unescape
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

url, thumb_dir = sys.argv[1], sys.argv[2]
UA = "Mozilla/5.0 (X11; Linux x86_64) quickshell-radio"
host = urlparse(url).netloc or url


def out(title, thumb=""):
    print(json.dumps({"title": (title or host).strip(), "thumb": thumb or ""}))
    sys.exit(0)


def download(img_url):
    try:
        req = Request(img_url, headers={"User-Agent": UA})
        with urlopen(req, timeout=10) as r:
            ctype = r.headers.get("Content-Type", "").split(";")[0].strip().lower()
            ext = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
                   "image/gif": "gif"}.get(ctype)
            if not ext:
                return ""
            data = r.read(5_000_000)
        os.makedirs(thumb_dir, exist_ok=True)
        path = os.path.join(thumb_dir, hashlib.sha1(url.encode()).hexdigest() + "." + ext)
        with open(path, "wb") as f:
            f.write(data)
        return path
    except Exception:
        return ""


def meta(html, *names):
    for n in names:
        for pat in (r'<meta[^>]+(?:property|name)=["\']%s["\'][^>]+content=["\']([^"\']+)' % n,
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']%s["\']' % n):
            m = re.search(pat, html, re.I)
            if m:
                return unescape(m.group(1)).strip()
    return ""


# 1) yt-dlp
if shutil.which("yt-dlp"):
    try:
        p = subprocess.run(["yt-dlp", "--no-playlist", "--skip-download", "--no-warnings",
                            "--print", "%(title)s", "--print", "%(thumbnail)s", url],
                           capture_output=True, text=True, timeout=25)
        lines = [l for l in p.stdout.splitlines() if l.strip()]
        if p.returncode == 0 and lines:
            t = lines[0]
            th = lines[1] if len(lines) > 1 and lines[1].startswith("http") else ""
            out(t, download(th) if th else "")
    except Exception:
        pass

# 2) plain page / raw stream
try:
    req = Request(url, headers={"User-Agent": UA, "Icy-MetaData": "1"})
    with urlopen(req, timeout=10) as r:
        ctype = r.headers.get("Content-Type", "").lower()
        if ctype.startswith("audio/") or r.headers.get("icy-name"):
            name = r.headers.get("icy-name", "")
            site = r.headers.get("icy-url", "")
            th = ""
            if site.startswith("http"):
                try:
                    with urlopen(Request(site, headers={"User-Agent": UA}), timeout=8) as s:
                        h = s.read(300_000).decode("utf-8", "ignore")
                    img = meta(h, "og:image", "twitter:image")
                    if img:
                        th = download(urljoin(site, img))
                except Exception:
                    pass
            out(name, th)
        html = r.read(300_000).decode("utf-8", "ignore")
    title = meta(html, "og:title", "twitter:title")
    if not title:
        m = re.search(r"<title[^>]*>(.*?)</title>", html, re.I | re.S)
        title = unescape(m.group(1)).strip() if m else ""
    img = meta(html, "og:image", "twitter:image")
    if not img:
        m = re.search(r'<link[^>]+rel=["\'](?:apple-touch-icon|icon)["\'][^>]+href=["\']([^"\']+)', html, re.I)
        img = m.group(1) if m else ""
    out(title, download(urljoin(url, img)) if img else "")
except SystemExit:
    raise
except Exception:
    out(host)
