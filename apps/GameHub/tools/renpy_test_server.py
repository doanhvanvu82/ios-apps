#!/usr/bin/env python3
"""Mẫu thử: chạy game Ren'Py bản PC bằng runtime web Ren'Py (không build lại).

    tools/renpy_test_server.py <thư-mục-game-pc> <thư-mục-runtime-web> [port]

Mô phỏng `RenPyNative` của app:
- game.zip dựng tại chỗ: `main.py` (= `<Tên>.py` ở gốc game, bản sao renpy.py),
  `renpy/` (bỏ .pyc Python 3.9 của bản PC) và các tệp nhỏ/script trong `game/`.
- Tệp lớn (ảnh, âm thanh, video…) liệt kê ở `gh_lazy.json`; `gamehub_lazyfs.js`
  gắn chúng vào FS và đọc theo Range (`?gh_b64=1`) khi Python mở tệp.
"""
import base64
import io
import pickle
import json
import os
import sys
import zipfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

GAME_DIR = os.path.abspath(sys.argv[1])
WEB_DIR = os.path.abspath(sys.argv[2])
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8100
LAZYFS_JS = os.path.join(os.path.dirname(__file__), "..", "Sources", "GameHub", "Resources",
                         "Runtime", "renpy", "gamehub_lazyfs.js")

SKIP_DIRS = {"saves", "cache", "__pycache__"}
SCRIPT_EXT = {".rpy", ".rpyc", ".rpym", ".rpymc", ".py", ".txt", ".json", ".tjs"}
INLINE_MAX = 64 * 1024  # tệp nhỏ hơn cho vào zip luôn (đỡ hàng nghìn XHR)
# Ren'Py web chỉ phát video qua URL ("video -" trong renpyweb_remote_files.txt);
# video đọc từ FS đi nhánh khác của _audio.js và video_stop ném TypeError.
VIDEO_EXT = {".ogv", ".webm", ".mp4", ".mkv", ".avi"}
# Ren'Py web là wasm32: offset > 2 GB trong tệp .rpa gây "Python int too large to
# convert to C long". Tách mỗi tệp con của rpa thành tệp riêng (giống RenPyNative).
RPA_SPLIT_MIN = 2 ** 31 - 1
VIRTUAL = {}  # "game/<tên>" → (đường dẫn rpa, offset, độ dài, prefix)


def rpa_entries(path):
    """RPA-3.0: dòng đầu "RPA-3.0 <offset hex> <key hex>", chỉ mục = pickle nén zlib."""
    import zlib
    with open(path, "rb") as fh:
        header = fh.readline().split()
        if not header or header[0] != b"RPA-3.0":
            return None
        offset, key = int(header[1], 16), int(header[2], 16)
        fh.seek(offset)
        index = pickle.loads(zlib.decompress(fh.read()), encoding="bytes")
    out = {}
    for name, parts in index.items():
        name = name.decode("utf-8") if isinstance(name, bytes) else name
        part = parts[0]
        prefix = part[2] if len(part) > 2 else b""
        if isinstance(prefix, str):
            prefix = prefix.encode("latin-1")
        out[name] = (part[0] ^ key, part[1] ^ key, prefix)
    return out


def build():
    buf = io.BytesIO()
    lazy = []
    videos = []
    zbytes = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
        main = next(f for f in sorted(os.listdir(GAME_DIR)) if f.endswith(".py"))
        z.write(os.path.join(GAME_DIR, main), "main.py")
        for top in ("renpy", "game"):
            for dp, dns, fns in os.walk(os.path.join(GAME_DIR, top)):
                # `_unpacked_archive`: bản giải nén trùng của .rpa (công cụ unrpa/unren)
                # → script .rpyc trùng → Ren'Py báo trùng label.
                dns[:] = [d for d in dns if d not in SKIP_DIRS and d != "_unpacked_archive"]
                for fn in fns:
                    full = os.path.join(dp, fn)
                    rel = os.path.relpath(full, GAME_DIR).replace(os.sep, "/")
                    if fn.endswith(".pyc") and os.path.exists(full[:-1]):
                        continue
                    size = os.path.getsize(full)
                    ext = os.path.splitext(fn)[1].lower()
                    if ext == ".rpa" and size > RPA_SPLIT_MIN:
                        entries = rpa_entries(full)
                        if entries is not None:
                            with open(full, "rb") as fh:
                                for inner, (off, length, prefix) in entries.items():
                                    vrel = "game/" + inner
                                    vext = os.path.splitext(inner)[1].lower()
                                    if vext in VIDEO_EXT:
                                        VIRTUAL[vrel] = (full, off, length, prefix)
                                        videos.append(inner)
                                    elif vext in SCRIPT_EXT or length + len(prefix) <= INLINE_MAX:
                                        fh.seek(off)
                                        z.writestr(vrel, prefix + fh.read(length))
                                    else:
                                        VIRTUAL[vrel] = (full, off, length, prefix)
                                        lazy.append([vrel, length + len(prefix)])
                            continue
                    if top == "game" and ext in VIDEO_EXT:
                        videos.append(rel[len("game/"):])
                    elif top == "renpy" or ext in SCRIPT_EXT or size <= INLINE_MAX:
                        z.write(full, rel)
                        zbytes += size
                    else:
                        lazy.append([rel, size])
        z.writestr("game/renpyweb_remote_files.txt", "".join("%s\nvideo -\n" % v for v in videos))
    print("[zip] %.1f MB trong zip, %d tệp lazy (%.1f MB), %d video qua URL" % (
        zbytes / 1e6, len(lazy), sum(s for _, s in lazy) / 1e6, len(videos)), flush=True)
    return buf.getvalue(), json.dumps(lazy).encode()


if os.environ.get("GH_ZIP"):  # dùng game.zip / gh_lazy.json do RenPyNative.swift dựng
    GAME_ZIP = open(os.environ["GH_ZIP"], "rb").read()
    LAZY_JSON = open(os.environ["GH_LAZY"], "rb").read()
else:
    GAME_ZIP, LAZY_JSON = build()
with open(os.path.join(WEB_DIR, "index.html"), encoding="utf-8") as fh:
    INDEX = fh.read()
if "gamehub_lazyfs.js" not in INDEX:  # runtime gốc chưa vá (bản trong app đã vá sẵn)
    INDEX = INDEX.replace('<script src="renpy-pre.js"></script>',
                          '<script src="renpy-pre.js"></script>\n  <script src="gamehub_lazyfs.js"></script>')
INDEX = INDEX.encode()


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_bytes(self, data, ctype, status=200):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path).lstrip("/") or "index.html"
        if path == "index.html":
            return self.send_bytes(INDEX, "text/html; charset=utf-8")
        if path == "game.zip":
            return self.send_bytes(GAME_ZIP, "application/zip")
        if path == "gh_lazy.json":
            return self.send_bytes(LAZY_JSON, "application/json")
        if path == "gamehub_lazyfs.js":
            with open(LAZYFS_JS, "rb") as fh:
                return self.send_bytes(fh.read(), "text/javascript")
        rng = self.headers.get("Range")
        if path in VIRTUAL and rng and "gh_b64=1" in parsed.query:
            rpa, off, length, prefix = VIRTUAL[path]
            a, _, b = rng.removeprefix("bytes=").partition("-")
            a, b = int(a), int(b)
            data = b""
            if a < len(prefix):
                data += prefix[a:b + 1]
            start = max(a - len(prefix), 0)
            end = b - len(prefix)
            if end >= start:
                with open(rpa, "rb") as fh:
                    fh.seek(off + start)
                    data += fh.read(end - start + 1)
            return self.send_bytes(base64.b64encode(data), "text/plain; charset=us-ascii")
        if path in VIRTUAL:  # video trong rpa — thẻ <video> tải qua URL
            rpa, off, length, prefix = VIRTUAL[path]
            with open(rpa, "rb") as fh:
                fh.seek(off)
                return self.send_bytes(prefix + fh.read(length), "video/webm")
        base = GAME_DIR if path.startswith("game/") else WEB_DIR
        full = os.path.normpath(os.path.join(base, path))
        if not full.startswith(base) or not os.path.isfile(full):
            return self.send_error(404)
        rng = self.headers.get("Range")
        if rng and "gh_b64=1" in parsed.query:
            a, _, b = rng.removeprefix("bytes=").partition("-")
            with open(full, "rb") as fh:
                fh.seek(int(a))
                data = fh.read(int(b) - int(a) + 1)
            return self.send_bytes(base64.b64encode(data), "text/plain; charset=us-ascii")
        with open(full, "rb") as fh:
            data = fh.read()
        ctype = ("application/wasm" if full.endswith(".wasm") else
                 "text/javascript" if full.endswith(".js") else "application/octet-stream")
        self.send_bytes(data, ctype)


if __name__ == "__main__":
    print("[server] http://127.0.0.1:%d/index.html" % PORT, flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
