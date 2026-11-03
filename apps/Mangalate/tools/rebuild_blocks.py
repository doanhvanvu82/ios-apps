#!/usr/bin/env python3
"""Dựng lại block từ `regions` đã lưu (không gọi OCR) rồi dịch lại cả chapter.

Dùng khi đổi quy tắc phân loại/gộp block/khung nền: OCR tốn quota nên giữ nguyên `regions`,
chỉ tính lại block rồi dựng lại ảnh.

    python3 tools/rebuild_blocks.py ../../.state/mangalate-review
    node tools/apply_layout.js ../../.state/mangalate-review
    python3 tools/rerender.py ../../.state/mangalate-review
"""

import json
import os
import sys

from PIL import Image

import render_test as harness


def chapters(root):
    for name in sorted(os.listdir(root)):
        folder = os.path.join(root, name)
        if not os.path.isdir(folder):
            continue
        pages = []
        for entry in sorted(os.listdir(folder)):
            if not entry.endswith(".json"):
                continue
            path = os.path.join(folder, entry)
            with open(path, encoding="utf-8") as handle:
                pages.append((path, json.load(handle)))
        if pages:
            yield name, pages


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "../../.state/mangalate-review"
    for name, pages in chapters(root):
        for path, data in pages:
            before = path[:-5] + ".before.png"
            image = Image.open(before).convert("RGB") if os.path.exists(before) else None
            data["blocks"] = harness.prepare(data.get("regions") or [], image)
        blocks = [block for _, data in pages for block in data["blocks"]]
        if blocks:
            harness.translate(blocks)
        for path, data in pages:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(data, handle, ensure_ascii=False, indent=1)
        print(f"{name}: {len(blocks)} block")


if __name__ == "__main__":
    main()
