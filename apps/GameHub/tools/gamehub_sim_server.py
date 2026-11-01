#!/usr/bin/env python3
"""Mô phỏng LocalWebServer của GameHub (kèm WebDAV PROPFIND) để test
luồng KiriKiri native (?webdavUrl=/) ngay trên máy — trước khi cài IPA.

Cách dùng: python3 gamehub_sim_server.py <thư_mục_game> [port]
"""
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GAME_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8095

# GH_NO_RUNTIME=1: phục vụ thẳng file game (RPG Maker…), không chèn runtime KiriKiri.
RUNTIME = "/nonexistent" if os.environ.get("GH_NO_RUNTIME") else os.path.expanduser(
    "~/Documents/Code/ios/apps/GameHub/Sources/GameHub/Resources/Runtime/kiriki")


def _xp3(files, xor_by_hash):
    """Giống KiriKiriPatch.archive: XP3 không nén, tuỳ chọn XOR theo adler32."""
    import struct, zlib
    header_len, body, index = 19, b"", b""
    for name, content in files:
        adler = zlib.adler32(content) & 0xFFFFFFFF
        stored = bytes(b ^ (adler & 0xFF) for b in content) if xor_by_hash else content
        info = struct.pack("<IQQH", 0, len(content), len(stored), len(name)) + name.encode("utf-16le")
        segm = struct.pack("<IQQQ", 0, header_len + len(body), len(content), len(stored))
        chunk = b"".join(tag + struct.pack("<Q", len(data)) + data for tag, data in
                         ((b"info", info), (b"segm", segm), (b"adlr", struct.pack("<I", adler))))
        index += b"File" + struct.pack("<Q", len(chunk)) + chunk
        body += stored
    return (b"XP3\r\n \n\x1a\x8b\x67\x01" + struct.pack("<Q", header_len + len(body)) + body
            + b"\x00" + struct.pack("<Q", len(index)) + index)


def _virtual_files():
    """Giống KiriKiriPatch.virtualFiles: patch.xp3 ảo giả lập json.dll."""
    plugins = os.listdir(os.path.join(GAME_DIR, "plugin")) if os.path.isdir(os.path.join(GAME_DIR, "plugin")) else []
    if "json.dll" not in (p.lower() for p in plugins):
        return {}
    loader = open(os.path.join(RUNTIME, "json_polyfill.tjs"), "rb").read() + (
        b'\nvar __ghOriginalLoader = System.exePath + "data.xp3>system/PluginLoader.tjs";\n'
        b"if (Storages.isExistentStorage(__ghOriginalLoader)) Scripts.execStorage(__ghOriginalLoader);\n")
    flt = os.path.join(GAME_DIR, "xp3filter.tjs")
    xor = os.path.isfile(flt) and "b.xor(0,l,h)" in open(flt, encoding="utf-8", errors="ignore").read().replace(" ", "")
    name, n = "patch.xp3", 2
    while os.path.exists(os.path.join(GAME_DIR, name)):
        name, n = "patch%d.xp3" % n, n + 1
    return {name: _xp3([("PluginLoader.tjs", loader)], xor)}


VIRTUAL = _virtual_files()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[sim] %s - %s\n" % (self.command, self.path))

    def _common_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Accept-Ranges", "bytes")

    def do_PROPFIND(self):
        # Đọc (và bỏ qua) request body — nếu không, body còn lại trong buffer
        # sẽ làm hỏng request kế tiếp trên cùng keep-alive connection (400).
        length = int(self.headers.get("Content-Length") or 0)
        if length > 0:
            self.rfile.read(length)
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        rel = path.strip("/")
        base = os.path.abspath(GAME_DIR)
        target = os.path.normpath(os.path.join(base, rel)) if rel else base
        if not target.startswith(base) or not os.path.isdir(target):
            self.send_error(404)
            return

        body = ['<?xml version="1.0" encoding="utf-8"?>',
                '<D:multistatus xmlns:D="DAV:">']
        root_href = "http://127.0.0.1:%d/" % PORT
        body.append(self._response(root_href, True, 0))
        names = set(os.listdir(target)) | (set(VIRTUAL) if not rel else set())
        for name in sorted(names):
            full = os.path.join(target, name)
            href = root_href + (rel + "/" if rel else "") + name
            if not rel and name in VIRTUAL:
                body.append(self._response(href, False, len(VIRTUAL[name])))
            elif os.path.isdir(full):
                body.append(self._response(href + "/", True, 0))
            else:
                body.append(self._response(href, False, os.path.getsize(full)))
        body.append("</D:multistatus>")
        data = "\n".join(body).encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._common_headers()
        self.end_headers()
        self.wfile.write(data)

    @staticmethod
    def _response(href, is_dir, size):
        rt = ("<D:resourcetype><D:collection/></D:resourcetype>" if is_dir
              else "<D:resourcetype/>")
        cl = "" if is_dir else "<D:getcontentlength>%d</D:getcontentlength>" % size
        return (f"<D:response><D:href>{href}</D:href>"
                f"<D:propstat><D:prop>{rt}{cl}</D:prop>"
                f"<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>")

    def do_HEAD(self):
        self.do_GET(head_only=True)

    def do_GET(self, head_only=False):
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        rel = path.lstrip("/")
        if not rel or rel.endswith("/"):
            rel += "index.html"

        if rel in VIRTUAL:
            data = VIRTUAL[rel]
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self._common_headers()
            self.end_headers()
            if not head_only:
                self.wfile.write(data)
            return

        base = os.path.abspath(GAME_DIR)
        if rel in ("index.html", "index.worker.js"):
            file_path = os.path.join(RUNTIME, "index.html")
        else:
            file_path = os.path.join(RUNTIME, rel)
        if not os.path.isfile(file_path):
            file_path = os.path.join(base, rel)
        file_path = os.path.normpath(file_path)
        if not (file_path.startswith(base) or file_path.startswith(os.path.abspath(RUNTIME))):
            self.send_error(403)
            return
        if not os.path.isfile(file_path):
            # Giống LocalWebServer.alternateVideoPath: X.mp4 <-> X.webm
            root, ext = os.path.splitext(file_path)
            alt = root + {".mp4": ".webm", ".webm": ".mp4"}.get(ext.lower(), ext)
            if alt != file_path and os.path.isfile(alt):
                file_path = alt
        if not os.path.isfile(file_path):
            self.send_error(404, "Not found: %s" % rel)
            return

        size = os.path.getsize(file_path)
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        partial = False
        if rng and rng.startswith("bytes="):
            spec = rng[6:].split(",")[0]
            a, _, b = spec.partition("-")
            if a:
                start = int(a)
                if b:
                    end = min(int(b), size - 1)
            elif b:
                start = max(0, size - int(b))
            partial = start > 0 or end < size - 1

        mime = "application/octet-stream"
        if rel.endswith(".html"):
            mime = "text/html"
        elif rel.endswith(".js"):
            mime = "text/javascript"
        elif rel.endswith(".wasm"):
            mime = "application/wasm"
        elif rel.endswith(".zip"):
            mime = "application/zip"

        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", mime)
        length = end - start + 1
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        self.send_header("Access-Control-Expose-Headers", "Content-Range, Accept-Ranges, Content-Length")
        self._common_headers()
        self.end_headers()
        if head_only:
            return
        with open(file_path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(1024 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Serving {GAME_DIR} (kiriki native sim) at http://127.0.0.1:{PORT}/")
    srv.serve_forever()
