#!/usr/bin/env python3
"""
Server test có header Cross-Origin Isolation (COOP/COEP).

Godot WebGL và KiriKiri (kirikiroid2-web) đều cần:
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
để bật SharedArrayBuffer (và JSPI cho KiriKiri).

Cách dùng:
  python3 tools/unity_test_server.py --coi <thư-mục> [port]
"""
import os
import sys
import http.server
import socketserver
import urllib.parse

COI = False
if "--coi" in sys.argv:
    sys.argv.remove("--coi")
    COI = True

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8099

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wasm": "application/wasm",
    ".data": "application/octet-stream",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".worker.js": "application/javascript; charset=utf-8",
    ".br": "application/octet-stream",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        path = urllib.parse.unquote(path)
        rel = path.lstrip("/") or "index.html"
        return os.path.join(ROOT, rel)

    def end_headers(self):
        if COI:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path) or not os.path.isfile(path):
            for suffix, enc in ((".br", "br"), (".gz", "gzip")):
                cand = path + suffix
                if os.path.isfile(cand):
                    path = cand
                    self._content_encoding = enc
                    break
        if not os.path.isfile(path):
            return super().send_head()

        ctype = MIME.get(os.path.splitext(path)[1].lower(), "application/octet-stream")
        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None

        fs = os.fstat(f.fileno())
        total = fs[6]

        # --- Hỗ trợ HTTP Range (bắt buộc với kirikiroid2-web: đọc ZIP theo range) ---
        # HEAD luôn trả 200 + Content-Length đầy đủ (đúng chuẩn HTTP).
        rng = self.headers.get("Range") if self.command != "HEAD" else None
        start, end = 0, total - 1
        status = 200
        if rng and rng.startswith("bytes="):
            spec = rng[6:].split(",")[0].strip()
            try:
                if spec.startswith("-"):
                    start = max(0, total - int(spec[1:]))
                elif "-" in spec:
                    a, b = spec.split("-", 1)
                    start = int(a)
                    end = int(b) if b else total - 1
                else:
                    start = int(spec)
                if start >= total:
                    raise ValueError
                end = min(end, total - 1)
                status = 206
            except ValueError:
                start, end, status = 0, total - 1, 200

        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        # Runtime kirikiroid2-web cần đọc được header Range từ JS.
        self.send_header(
            "Access-Control-Expose-Headers",
            "Content-Length, Content-Range, Accept-Ranges, ETag, Last-Modified",
        )
        if getattr(self, "_content_encoding", None):
            self.send_header("Content-Encoding", self._content_encoding)
        self.end_headers()
        self._range = (start, length) if status == 206 else None
        return f

    def copyfile(self, source, outputfile):
        """Chỉ ghi đúng phần byte theo Range đã yêu cầu."""
        rng = getattr(self, "_range", None)
        if rng is None:
            return super().copyfile(source, outputfile)
        start, length = rng
        source.seek(start)
        remaining = length
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)

    def log_message(self, fmt, *args):
        sys.stderr.write("[test-server] " + (fmt % args) + "\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        mode = "COI bật" if COI else "thường"
        print(f"Serving {ROOT} at http://127.0.0.1:{PORT}/ ({mode})", flush=True)
        httpd.serve_forever()
