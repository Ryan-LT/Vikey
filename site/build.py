#!/usr/bin/env python3
"""Builds site/dist from site/pages/*.html by wrapping each page in the shared layout (nav + footer).
No dependencies. Run: python3 site/build.py
Demo frames (assets/demo.json) come from the real engine: Tools/autoswitch/test/harness frames <lang> <keys>."""
import os, re, shutil, datetime, json

ROOT = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(ROOT, "pages")
DIST = os.path.join(ROOT, "dist")
YEAR = datetime.date.today().year
SITE = "https://vikey.app"
GITHUB = "https://github.com/tonyminibot/Vikey"

NAV = f"""<header class="nav"><div class="wrap">
<a class="brand" href="/"><img src="/assets/icon.png" alt="" width="34" height="34"><span>Vi<b>key</b></span></a>
<nav><a href="/faq">Câu hỏi</a><a href="/changelog">Phiên bản</a><a href="{GITHUB}">GitHub</a><a class="btn dl-direct" href="DOWNLOAD_URL" download>Tải về</a></nav>
<button class="menu-btn" type="button" aria-label="Menu" aria-expanded="false" aria-controls="mnav"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg></button>
</div>
<nav class="mnav" id="mnav" hidden><a href="/download">Tải về</a><a href="/faq">Câu hỏi</a><a href="/changelog">Phiên bản</a><a href="{GITHUB}">GitHub</a></nav>
</header>
<script>(()=>{{const b=document.querySelector(".menu-btn"),m=document.getElementById("mnav");if(!b)return;b.onclick=()=>{{const o=m.hidden;m.hidden=!o;b.setAttribute("aria-expanded",o)}};addEventListener("keydown",e=>{{if(e.key==="Escape"){{m.hidden=true;b.setAttribute("aria-expanded",false)}}}})}})()</script>
<script>if(matchMedia("(max-width:900px),(pointer:coarse)").matches)document.querySelectorAll("a.dl-direct,a.dl-mac").forEach(a=>{{a.href="/download";a.removeAttribute("download")}})</script>"""

FOOTER = f"""<footer class="foot"><div class="wrap cols">
<div class="col"><p class="muted">© {YEAR} Tony Dinh. Dựa trên <a href="https://github.com/tuyenvm/OpenKey">OpenKey</a> của Tuyen Mai. Mã nguồn mở theo giấy phép GPL-3.0.</p></div>
<div class="col"><h4>Vikey</h4><a href="/">Trang chủ</a><a href="/download">Tải về</a><a href="/changelog">Phiên bản</a></div>
<div class="col"><h4>Hỗ trợ</h4><a href="/faq">Câu hỏi thường gặp</a><a href="{GITHUB}/issues">Báo lỗi</a><a href="/privacy">Quyền riêng tư</a></div>
<div class="col"><h4>Mã nguồn</h4><a href="{GITHUB}">GitHub</a><a href="{GITHUB}/blob/main/LICENSE">Giấy phép GPL-3.0</a><a href="https://x.com/tdinh_me">@tdinh_me</a></div>
</div></footer>"""

HEAD = """<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="icon" href="/assets/icon.png"><link rel="apple-touch-icon" href="/assets/icon.png">
<meta property="og:site_name" content="Vikey - Gõ tiếng Việt"><meta name="application-name" content="Vikey - Gõ tiếng Việt"><meta property="og:title" content="{title}"><meta property="og:description" content="{description}">
<meta property="og:image" content="{site}/assets/og.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:type" content="website"><meta property="og:url" content="{site}{path}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{site}/assets/og.png">
{canonical}
<link rel="stylesheet" href="/style.css?v={ver}">
</head><body{bodyclass}>"""

def release():
    p = os.path.join(ROOT, "release.json")
    return json.load(open(p)) if os.path.exists(p) else {}

def build():
    rel = release()
    if os.path.exists(DIST): shutil.rmtree(DIST)
    shutil.copytree(os.path.join(ROOT, "assets"), os.path.join(DIST, "assets"))
    if os.path.isdir(os.path.join(ROOT, "downloads")):
        shutil.copytree(os.path.join(ROOT, "downloads"), os.path.join(DIST, "downloads"))
    shutil.copy(os.path.join(ROOT, "style.css"), DIST)
    if rel: shutil.copy(os.path.join(ROOT, "release.json"), DIST)
    if os.path.exists(os.path.join(ROOT, "appcast.xml")): shutil.copy(os.path.join(ROOT, "appcast.xml"), DIST)   # Sparkle feed
    ver = str(int(os.path.getmtime(os.path.join(ROOT, "style.css"))))
    for name in sorted(os.listdir(PAGES)):
        if not name.endswith(".html"): continue
        src = open(os.path.join(PAGES, name), encoding="utf-8").read()
        meta = dict(re.findall(r"<!--\s*(\w+):\s*(.*?)\s*-->", "\n".join(src.split("\n")[:6])))
        body = re.sub(r"^(<!--.*?-->\s*)+", "", src, flags=re.S)
        slug = name[:-5]
        path = "/" if slug == "index" else "/" + slug
        canonical = '<meta name="robots" content="noindex">' if meta.get("noindex") else f'<link rel="canonical" href="{SITE}{path}">'
        one = meta.get("layout") == "one"
        page = HEAD.format(title=meta.get("title", "Vikey"), description=meta.get("description", ""), site=SITE, path=path, ver=ver,
                           canonical=canonical, bodyclass=' class="one-page"' if one else "")
        page += NAV + body + ("" if one else FOOTER) + "</body></html>\n"
        for k, v in {"VERSION": rel.get("version"), "DOWNLOAD_URL": rel.get("download_url"), "SHA256": rel.get("sha256")}.items():
            if v: page = page.replace(k, v)
        # cache-bust assets: /assets/x.png -> /assets/x.png?v=<mtime>, so browsers never show a stale screenshot
        def bust(m):
            f = os.path.join(ROOT, m.group(1).lstrip("/"))
            return m.group(0) if not os.path.exists(f) else f'{m.group(1)}?v={int(os.path.getmtime(f))}"'
        page = re.sub(r'(/assets/[\w./-]+\.(?:png|json|svg|jpg))"', bust, page)
        out = os.path.join(DIST, "index.html" if slug == "index" else f"{slug}.html")
        open(out, "w", encoding="utf-8").write(page)
    open(os.path.join(DIST, "_headers"), "w").write("/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n/downloads/*\n  Content-Disposition: attachment\n")
    open(os.path.join(DIST, "robots.txt"), "w").write(f"User-agent: *\nAllow: /\nSitemap: {SITE}/sitemap.xml\n")
    pages = [n[:-5] for n in os.listdir(PAGES) if n.endswith(".html") and n != "404.html"]
    urls = "".join(f"<url><loc>{SITE}{'/' if p == 'index' else '/' + p}</loc></url>" for p in sorted(pages))
    open(os.path.join(DIST, "sitemap.xml"), "w").write(f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n')
    print("built", len(os.listdir(DIST)), "entries into site/dist")

if __name__ == "__main__":
    build()
