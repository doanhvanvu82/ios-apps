#!/usr/bin/env python3
"""Test server mô phỏng GameHub cho game Godot native.

- Phục vụ thư mục game ở gốc.
- Phục vụ file runtime (godot3/godot4) làm fallback.
- Sinh index.html đúng như `EngineRuntime.godotIndexHTML` của app.
"""
import os
import sys
import json
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import unquote, urlparse

GAME_DIR = sys.argv[1]
RUNTIME_DIR = sys.argv[2]
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8098
RUNTIME_KIND = sys.argv[4] if len(sys.argv) > 4 else "godot3"

# Chọn pck chính: ưu tiên trùng tên exe, không thì pck lớn nhất
items = os.listdir(GAME_DIR)
candidates = [f for f in items if f.endswith(".pck")]
exe_names = {os.path.splitext(f)[0] for f in items if f.endswith(".exe")}
main_pck = next((c for c in candidates if os.path.splitext(c)[0] in exe_names), None)
if main_pck is None and candidates:
    main_pck = max(candidates, key=lambda f: os.path.getsize(os.path.join(GAME_DIR, f)))

# Giống GodotPack.embeddedPack: không có .pck rời → pck nhúng cuối .exe
# (12 byte cuối = size UInt64 LE + "GDPC"), phục vụ dưới tên game.pck.
PCK_SLICE = None
if main_pck is None:
    for f in items:
        if f.lower().endswith(".exe"):
            exe = os.path.join(GAME_DIR, f)
            with open(exe, "rb") as fh:
                fh.seek(-12, 2)
                trailer = fh.read(12)
            if trailer[8:] == b"GDPC":
                size = int.from_bytes(trailer[:8], "little")
                PCK_SLICE = (exe, os.path.getsize(exe) - 12 - size, size)
                main_pck = "game.pck"
                break

if PCK_SLICE:
    pack_size = PCK_SLICE[2]
    with open(PCK_SLICE[0], "rb") as fh:
        fh.seek(PCK_SLICE[1])
        hdr = fh.read(20)
else:
    pack_size = os.path.getsize(os.path.join(GAME_DIR, main_pck))
    with open(os.path.join(GAME_DIR, main_pck), "rb") as fh:
        hdr = fh.read(20)
wasm_size = os.path.getsize(os.path.join(RUNTIME_DIR, "index.wasm"))
major = int.from_bytes(hdr[8:12], "little")
minor = int.from_bytes(hdr[12:16], "little")
print(f"[config] pck={main_pck} ({pack_size/1e6:.1f}MB) godot={major}.{minor} "
      f"wasm={wasm_size/1e6:.1f}MB runtime={RUNTIME_KIND}")

CONFIG = {
    "args": [],
    "canvasResizePolicy": 2,
    "executable": "index",
    "mainPack": main_pck,
    "experimentalVK": False,
    "fileSizes": {main_pck: pack_size, "index.wasm": wasm_size},
    "focusCanvas": True,
    "gdextensionLibs": [],
}

with open(os.path.join(RUNTIME_DIR, "godot.html"), encoding="utf-8") as fh:
    template = fh.read()

INDEX_HTML = (template
              .replace("$GODOT_PROJECT_NAME", os.path.basename(GAME_DIR))
              .replace("$GODOT_HEAD_INCLUDE", "")
              .replace("$GODOT_URL", "index.js" if RUNTIME_KIND == "godot45" else "godot.js")
              .replace("$GODOT_CONFIG", json.dumps(CONFIG, separators=(",", ":"))))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=GAME_DIR, **kw)

    def log_message(self, fmt, *args):
        sys.stderr.write("[http] %s\n" % (fmt % args))

    def end_headers(self):
        # COEP require-corp → mọi sub-resource phải có CORP header,
        # nếu không sẽ bị chặn với ERR_BLOCKED_BY_RESPONSE.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def do_GET(self):
        path = unquote(urlparse(self.path).path).lstrip("/")
        if path == "index.html":
            data = INDEX_HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        rng = self.headers.get("Range")
        if PCK_SLICE and path == main_pck:
            b64 = "gh_b64=1" in urlparse(self.path).query.split("&")
            return self._serve_range(PCK_SLICE[0], rng or "bytes=0-", b64, PCK_SLICE[1], PCK_SLICE[2])
        # ưu tiên file trong thư mục game, fallback runtime
        local = os.path.join(GAME_DIR, path)
        if os.path.isfile(local) and rng:
            b64 = "gh_b64=1" in urlparse(self.path).query.split("&")
            return self._serve_range(local, rng, b64)
        if os.path.isfile(local):
            return super().do_GET()
        rt = os.path.join(RUNTIME_DIR, path)
        if os.path.isfile(rt):
            self.path = "/" + path
            return super().do_GET()
        self.send_error(404)

    # Giống LocalWebServer.serveRange: runtime Godot 3 đọc pck lazy bằng Range.
    def _serve_range(self, file_path, rng, b64=False, base=0, size=None):
        size = os.path.getsize(file_path) if size is None else size
        start_s, _, end_s = rng.removeprefix("bytes=").partition("-")
        start = int(start_s)
        end = min(int(end_s) if end_s else size - 1, size - 1)
        if start > end:
            self.send_error(416)
            return
        if b64:  # giống LocalWebServer ?gh_b64=1: base64 cho XHR đồng bộ (Godot 4)
            import base64
            with open(file_path, "rb") as fh:
                fh.seek(base + start)
                data = base64.b64encode(fh.read(end - start + 1))
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=us-ascii")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(file_path, "rb") as fh:
            fh.seek(base + start)
            self.wfile.write(fh.read(end - start + 1))

    def translate_path(self, path):
        path = unquote(urlparse(path).path)
        rel = path.lstrip("/")
        if rel and os.path.isfile(os.path.join(RUNTIME_DIR, rel)) \
                and not os.path.isfile(os.path.join(GAME_DIR, rel)):
            return os.path.join(RUNTIME_DIR, rel)
        return os.path.join(GAME_DIR, rel)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[server] http://127.0.0.1:{PORT}/index.html")
    srv.serve_forever()
