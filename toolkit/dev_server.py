#!/usr/bin/env python3
"""Server LAN cho iPhone (chạy nền qua toolkit/serve_sidestore.sh).

- GET  /…          → file trong sidestore/ (source SideStore chung + IPA mọi app).
- POST /clipboard  → đặt body (UTF-8) vào clipboard máy tính, lưu thêm ra
                     .state/iphone_clipboard.txt. App gọi từ nút "Gửi về máy
                     tính" (vd: màn Log của GameHub).
- POST /log        → chỉ ghi body ra .state/iphone_log.txt (không đụng clipboard),
                     cho app tự gửi log chẩn đoán liên tục.

Clipboard đặt qua Tk (có sẵn trong Python): GNOME tự đồng bộ clipboard XWayland
sang Wayland. Tk phải chạy ở main thread, nên HTTP server chạy ở thread phụ và
đẩy nội dung qua hàng đợi.
"""
import os
import queue
import sys
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVE_DIR = os.path.join(ROOT, "sidestore")
# Ngoài SERVE_DIR để máy khác trong LAN không tải được.
CLIP_FILE = os.path.join(ROOT, ".state", "iphone_clipboard.txt")
LOG_FILE = os.path.join(ROOT, ".state", "iphone_log.txt")
MAX_BODY = 20 * 1024 * 1024
clips = queue.Queue()


class Handler(SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path not in ("/clipboard", "/log"):
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self.send_error(413 if length > MAX_BODY else 400)
            return
        text = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(LOG_FILE if self.path == "/log" else CLIP_FILE, "w", encoding="utf-8") as fh:
            fh.write(text)
        if self.path == "/clipboard":
            clips.put(text)
        body = b"ok"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        sys.stderr.write("[%s] nhận %d ký tự\n" % (self.path[1:], len(text)))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    os.makedirs(SERVE_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(CLIP_FILE), exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", port), partial(Handler, directory=SERVE_DIR))
    threading.Thread(target=server.serve_forever, daemon=True).start()

    try:
        import tkinter
        root = tkinter.Tk()
        root.withdraw()
    except Exception as exc:  # không có màn hình → chỉ lưu file
        sys.stderr.write("[clipboard] Tk không chạy được (%s) — chỉ lưu %s\n" % (exc, CLIP_FILE))
        threading.Event().wait()
        return

    def poll():
        try:
            while True:
                text = clips.get_nowait()
                root.clipboard_clear()
                root.clipboard_append(text)
                root.update()
        except queue.Empty:
            pass
        root.after(200, poll)

    poll()
    root.mainloop()


if __name__ == "__main__":
    main()
