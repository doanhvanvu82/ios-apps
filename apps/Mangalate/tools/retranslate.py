#!/usr/bin/env python3
"""Dịch lại toàn bộ block trong thư mục review có sẵn, không gọi OCR.

Dùng khi chỉ đổi quy tắc dịch (prompt, cách gộp câu): không cần chạy lại OCR tốn quota.
Dịch cả chapter trong một lượt để xưng hô/tên riêng nhất quán, sau đó dựng lại ảnh.

    python3 tools/retranslate.py ../../.state/mangalate-review
"""

import json
import os
import sys

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
        blocks = [block for _, data in pages for block in data.get("blocks") or []]
        if not blocks:
            continue
        for block in blocks:
            block.pop("translation", None)
        harness.translate(blocks)
        for path, data in pages:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(data, handle, ensure_ascii=False, indent=1)
        print(f"{name}: {len(blocks)} block")


if __name__ == "__main__":
    main()
