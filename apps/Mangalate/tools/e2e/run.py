#!/usr/bin/env python3
"""Chạy content script thật trên Chromium (Playwright) với từng chapter, chụp ảnh trước/sau từng trang.

    python3 tools/e2e/run.py <thư mục chứa các chapter> [tên chapter ...]

Mỗi chapter là một thư mục ảnh. Kết quả: .state/mangalate-e2e/<chapter>/
    NNN.png      — trái: ảnh gốc, phải: sau khi dán (chữ gốc đặt lại lên nền, không dịch)
    report.json  — chẩn đoán content script (block giữ/bỏ, log) + log native
Playwright WebKit trên máy này thiếu thư viện hệ thống (libjxl0.8, libbacktrace0) nên dùng Chromium:
chọn ô thoại/khung giống hệt, chỉ cách dàn chữ có thể lệch nhẹ so với Safari.
Cần: Playwright cho Python (Chromium), venv .state/mangalate-venv có rapidocr_onnxruntime,
và .state/mangalate/native-harness (xem tools/native-harness/build.sh).
"""

import json
import os
import socket
import subprocess
import sys
import time

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
VENV_PYTHON = os.path.join(REPO, ".state", "mangalate-venv", "bin", "python")
OUT_ROOT = os.path.join(REPO, ".state", "mangalate-e2e")
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
# Màn hình iPhone cỡ thường: ảnh truyện hiển thị theo bề ngang viewport như khi đọc trên Safari.
VIEWPORT = {"width": 430, "height": 932}
SCALE = 2
TIMEOUT_S = 1800


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def side_by_side(before, after, path):
    left, right = Image.open(before), Image.open(after)
    canvas = Image.new("RGB", (left.width + right.width + 12, max(left.height, right.height)), "#ff00ff")
    canvas.paste(left, (0, 0))
    canvas.paste(right, (left.width + 12, 0))
    canvas.save(path)
    os.remove(before)
    os.remove(after)


def run_chapter(page, port, chapter, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    page.goto(f"http://127.0.0.1:{port}/c/{chapter}", wait_until="load")
    page.wait_for_function("Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)")
    page.wait_for_function("window.__harness && __harness.fabText() === 'Dịch'", timeout=15000)
    started = time.time()
    page.evaluate("__harness.send({type: 'translateNow'})")
    while True:
        fab, panel = page.evaluate("[__harness.fabText(), __harness.panelText()]")
        if panel or fab == "Bản gốc":
            break
        if time.time() - started > TIMEOUT_S:
            panel = f"hết thời gian chờ (fab: {fab})"
            break
        time.sleep(1)
    elapsed = time.time() - started
    page.wait_for_timeout(1200)  # saveDiag ghi trễ 500 ms.
    diag = page.evaluate("__harness.store['mangalate:lastRun'] || null")
    blocks = page.evaluate("__harness.blocks()") or []
    for block in blocks:
        block["src"] = block.get("src", "").rsplit("/", 1)[-1]
    with open(os.path.join(out_dir, "blocks.json"), "w", encoding="utf-8") as fh:
        json.dump(blocks, fh, ensure_ascii=False)

    # Nút nổi che góc ảnh trong ảnh chụp; click() vẫn chạy khi nút bị ẩn.
    page.evaluate("document.getElementById('mangalate-ui').shadowRoot.querySelector('.fab').style.visibility = 'hidden'")
    images = page.locator("img")
    count = images.count()
    for index in range(count):
        after = os.path.join(out_dir, f"{index:03d}.after.png")
        images.nth(index).screenshot(path=after)
    page.evaluate("__harness.clickFab()")  # Bản gốc: ẩn lớp dán.
    page.wait_for_timeout(300)
    for index in range(count):
        before = os.path.join(out_dir, f"{index:03d}.before.png")
        images.nth(index).screenshot(path=before)
        side_by_side(before, os.path.join(out_dir, f"{index:03d}.after.png"), os.path.join(out_dir, f"{index:03d}.png"))

    report = {"chapter": chapter, "seconds": round(elapsed, 1), "panel": panel, "images": count, "diag": diag}
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
    return report


def main():
    root = os.path.abspath(sys.argv[1])
    wanted = sys.argv[2:]
    chapters = wanted or sorted(
        name for name in os.listdir(root)
        if os.path.isdir(os.path.join(root, name)) and not name.startswith(("_", "."))
        and any(f.lower().endswith(IMAGE_EXT) for f in os.listdir(os.path.join(root, name)))
    )
    port = free_port()
    os.makedirs(OUT_ROOT, exist_ok=True)
    server = subprocess.Popen(
        [VENV_PYTHON, os.path.join(HERE, "server.py"), root, str(port), os.path.join(OUT_ROOT, "native.log")],
        stdout=subprocess.PIPE, text=True,
    )
    try:
        if server.stdout.readline().strip() != "ready":
            raise SystemExit("server không khởi động được")
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            context = browser.new_context(viewport=VIEWPORT, device_scale_factor=SCALE)
            for chapter in chapters:
                page = context.new_page()
                report = run_chapter(page, port, chapter, os.path.join(OUT_ROOT, chapter))
                diag = report["diag"] or {}
                print(f"{chapter}: {report['seconds']}s · block {diag.get('total')} · gửi {diag.get('sent')} · "
                      f"dán {diag.get('translated')} · {report['panel'] or 'ok'}", flush=True)
                page.close()
            browser.close()
    finally:
        server.terminate()


if __name__ == "__main__":
    main()
