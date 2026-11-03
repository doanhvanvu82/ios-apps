#!/usr/bin/env python3
"""Vẽ lại .after.png từ JSON có sẵn (không gọi Gemini).

Dùng khi đổi quy tắc dán chữ/vùng đặt chữ: chạy apply_layout.js để cập nhật `textArea`
trong JSON, rồi script này dựng lại ảnh — khỏi tốn quota để OCR/dịch lại.

    node tools/apply_layout.js ../../.state/mangalate-review
    python3 tools/rerender.py ../../.state/mangalate-review
"""

import json
import os
import sys

from render_test import render


def collect(root):
    for name in sorted(os.listdir(root)):
        folder = os.path.join(root, name)
        if not os.path.isdir(folder):
            continue
        for entry in sorted(os.listdir(folder)):
            if entry.endswith(".after.png"):
                stem = entry[: -len(".after.png")]
                yield os.path.join(folder, stem + ".json"), os.path.join(folder, stem + ".before.png"), os.path.join(folder, entry)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "../../.state/mangalate-review"
    pages = 0
    for meta, before, after in collect(root):
        if not (os.path.exists(meta) and os.path.exists(before)):
            continue
        with open(meta, encoding="utf-8") as handle:
            blocks = json.load(handle).get("blocks") or []
        render(before, blocks, after)
        pages += 1
    print(f"{pages} trang đã vẽ lại")


if __name__ == "__main__":
    main()
