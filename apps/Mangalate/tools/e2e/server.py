#!/usr/bin/env python3
"""Server cho harness E2E: phục vụ trang thử + đóng vai background.js và appex.

Content script thật (WebExtension/content/*.js) chạy trong WebKit, cắt ảnh thành tile JPEG và gửi
`ocr` như trên iPhone. Server thay Vision bằng RapidOCR rồi chạy phần phân tích pixel của appex
(PageAnalyzer + PixelGrid biên dịch cho Linux: .state/mangalate/native-harness). `translate` trả lại
nguyên văn chữ gốc — harness chỉ kiểm tra chọn ô thoại và cách dán chữ, không kiểm tra bản dịch.

Chạy bằng venv có rapidocr_onnxruntime (tools/e2e/run.py tự bật):
    .state/mangalate-venv/bin/python tools/e2e/server.py <thư mục chapter> <port>
"""

import base64
import hashlib
import html
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(APP, "..", ".."))
STATE = os.path.join(REPO, ".state", "mangalate")
NATIVE = os.path.join(STATE, "native-harness")
OCR_CACHE = os.path.join(STATE, "ocr-cache")
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
# Vision bỏ dòng có độ tin cậy dưới ngưỡng này (TextRecognizer.recognizeLines).
MIN_CONFIDENCE = 0.25
# Vision tự nhận chữ Hàn; RapidOCR mặc định chỉ đọc Trung/Anh nên manhwa raw cần model riêng:
# MANGALATE_OCR_LANG=ko (model + dict tải vào .state/mangalate/ocr-models từ RapidAI/RapidOCR trên ModelScope).
OCR_LANG = os.environ.get("MANGALATE_OCR_LANG", "")
OCR_MODELS = {
    "ko": ("korean_PP-OCRv4_rec_mobile.onnx", "korean_dict.txt"),
}

_engine = None
# RapidOCR không an toàn khi gọi song song (content script OCR 2 ảnh một lúc).
_engine_lock = threading.Lock()


def engine():
    global _engine
    if _engine is None:
        from rapidocr_onnxruntime import RapidOCR
        if OCR_LANG:
            model, keys = (os.path.join(STATE, "ocr-models", name) for name in OCR_MODELS[OCR_LANG])
            _engine = RapidOCR(rec_model_path=model, rec_keys_path=keys)
        else:
            _engine = RapidOCR()
    return _engine


def recognize(image):
    """Dòng chữ trong ảnh như Vision: [{text, confidence, box:[x,y,w,h] pixel}]. Có cache theo nội dung ảnh."""
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    key = hashlib.sha1(buffer.getvalue()).hexdigest() + (f".{OCR_LANG}" if OCR_LANG else "")
    path = os.path.join(OCR_CACHE, key + ".json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    with _engine_lock:
        result, _ = engine()(image)
    lines = []
    for quad, text, score in result or []:
        text = str(text).strip()
        if not text or float(score) < MIN_CONFIDENCE:
            continue
        xs = [point[0] for point in quad]
        ys = [point[1] for point in quad]
        x0, y0 = max(0.0, min(xs)), max(0.0, min(ys))
        x1, y1 = min(float(image.width), max(xs)), min(float(image.height), max(ys))
        if x1 <= x0 or y1 <= y0:
            continue
        lines.append({"text": text, "confidence": float(score), "box": [x0, y0, x1 - x0, y1 - y0]})
    os.makedirs(OCR_CACHE, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(lines, fh, ensure_ascii=False)
    return lines


def native_ocr(image):
    """Giống SafariWebExtensionHandler `ocr`: thu nhỏ + chia tile như appex, OCR, phân tích pixel."""
    image = image.convert("RGB")
    plan = json.loads(subprocess.run([NATIVE, "plan", str(image.width), str(image.height)],
                                     capture_output=True, text=True, check=True).stdout)
    if (plan["width"], plan["height"]) != image.size:
        image = image.resize((plan["width"], plan["height"]), Image.BICUBIC)
    with tempfile.TemporaryDirectory() as work:
        tiles = []
        for index, (x, y, w, h) in enumerate(plan["tiles"]):
            tile = image.crop((x, y, x + w, y + h))
            raw = f"tile{index}.raw"
            with open(os.path.join(work, raw), "wb") as fh:
                fh.write(tile.convert("RGBA").tobytes())
            tiles.append({"origin": [x, y], "rgba": raw, "width": w, "height": h, "lines": recognize(tile)})
        job = os.path.join(work, "job.json")
        with open(job, "w", encoding="utf-8") as fh:
            json.dump({"width": image.width, "height": image.height, "tiles": tiles}, fh, ensure_ascii=False)
        out = subprocess.run([NATIVE, "analyze", job], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def decode_data_url(value):
    _, _, payload = value.partition(",")
    return Image.open(io.BytesIO(base64.b64decode(payload)))


def handle_native(payload, log):
    action = payload.get("action")
    if action == "ocr":
        return {"ok": True, "lines": native_ocr(decode_data_url(payload["image"]))}
    if action == "translate":
        # Không dịch: trả chữ gốc để xem chữ đặt lên nền có đúng chỗ/cỡ không.
        return {"ok": True, "translations": [{"id": b["id"], "text": b["text"]} for b in payload.get("blocks", [])]}
    if action == "analyze":
        return {"ok": True, "context": ""}
    if action == "log":
        log(str(payload.get("text", "")))
        return {"ok": True}
    return {"ok": False, "error": f"harness không hỗ trợ action {action}"}


def handle_background(message, log):
    kind = message.get("type")
    if kind == "getSettings":
        return {"ok": True, "result": {"hasKey": True, "model": "harness", "offline": False}}
    if kind == "log":
        log(str(message.get("text", "")))
        return {"ok": True, "result": {"logged": True}}
    if kind == "native":
        reply = handle_native(message.get("payload") or {}, log)
        if not reply.get("ok"):
            return {"ok": False, "error": reply.get("error")}
        return {"ok": True, "result": reply}
    return {"ok": False, "error": f"lệnh không hợp lệ: {kind}"}


def chapter_page(chapter, files):
    images = "\n".join(
        f'<img src="/c/{html.escape(chapter)}/{html.escape(name)}" alt="">' for name in files
    )
    return f"""<!doctype html>
<html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{{margin:0;background:#222}} img{{display:block;width:100%;height:auto}}</style>
<script src="/harness/shim.js"></script>
<script src="/ext/content/translate-core.js"></script>
<script src="/ext/content/translate.js" defer></script>
</head><body>
{images}
</body></html>"""


def make_handler(root, log_path):
    log_lock = threading.Lock()

    def log(text):
        with log_lock, open(log_path, "a", encoding="utf-8") as fh:
            fh.write(text + "\n")

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send_bytes(self, body, content_type, status=200):
            self.send_response(status)
            self.send_header("content-type", content_type)
            self.send_header("content-length", str(len(body)))
            self.send_header("cache-control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def send_file(self, path):
            if not os.path.isfile(path):
                self.send_bytes(b"not found", "text/plain", 404)
                return
            types = {".js": "text/javascript; charset=utf-8", ".png": "image/png", ".webp": "image/webp"}
            content_type = types.get(os.path.splitext(path)[1].lower(), "image/jpeg")
            with open(path, "rb") as fh:
                self.send_bytes(fh.read(), content_type)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            parts = [p for p in path.split("/") if p]
            if parts[:1] == ["ext"]:
                self.send_file(os.path.join(APP, "WebExtension", *parts[1:]))
            elif parts == ["harness", "shim.js"]:
                self.send_file(os.path.join(HERE, "shim.js"))
            elif parts[:1] == ["c"] and len(parts) == 2:
                folder = os.path.join(root, parts[1])
                files = sorted(f for f in os.listdir(folder) if f.lower().endswith(IMAGE_EXT))
                self.send_bytes(chapter_page(parts[1], files).encode(), "text/html; charset=utf-8")
            elif parts[:1] == ["c"] and len(parts) == 3:
                self.send_file(os.path.join(root, parts[1], parts[2]))
            else:
                self.send_bytes(b"not found", "text/plain", 404)

        def do_POST(self):
            if self.path != "/bg":
                self.send_bytes(b"not found", "text/plain", 404)
                return
            length = int(self.headers.get("content-length", "0"))
            message = json.loads(self.rfile.read(length) or b"{}")
            try:
                reply = handle_background(message, log)
            except Exception as error:  # Lỗi harness phải hiện ra trên trang như lỗi native.
                reply = {"ok": False, "error": f"harness: {error}"}
            self.send_bytes(json.dumps(reply, ensure_ascii=False).encode(), "application/json")

    return Handler


def main():
    root, port = sys.argv[1], int(sys.argv[2])
    log_path = sys.argv[3] if len(sys.argv) > 3 else os.devnull
    engine()
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(root, log_path))
    print("ready", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
