#!/usr/bin/env python3
"""Chấm bộ lọc ô thoại bằng dữ liệu chuẩn OpenMantra (toạ độ chữ thoại do người gán).

    python3 tools/e2e/score.py <open-mantra-dataset> <thư mục chapter ảnh> [--search]

Đọc .state/mangalate-e2e/OpenMantra-<bộ>/blocks.json (run.py ghi) và annotation.json của bộ dữ liệu.
Block "đúng" = tâm hộp chữ nằm trong một hộp chữ chuẩn (nới 1% trang). Báo precision (block giữ lại
là thoại thật) và recall (hộp chữ chuẩn có ít nhất một block giữ lại). --search thử lưới ngưỡng
fill/enclose để xem quy tắc nào tốt hơn quy tắc hiện tại.
"""

import itertools
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".state", "mangalate-e2e"))
PAD = 0.01


def load_truth(dataset, images_root):
    with open(os.path.join(dataset, "annotation.json"), encoding="utf-8") as fh:
        books = json.load(fh)
    truth = {}
    for book in books:
        chapter = "OpenMantra-" + book["book_title"]
        folder = os.path.join(images_root, chapter)
        if not os.path.isdir(folder):
            continue
        for page in book["pages"]:
            name = os.path.basename(page["image_paths"]["ja"])
            width, height = Image.open(os.path.join(folder, name)).size
            truth[(chapter, name)] = [
                (t["x"] / width, t["y"] / height, t["w"] / width, t["h"] / height) for t in page["text"]
            ]
    return truth


def matches(block, box):
    text = block.get("textBox") or block["box"]
    cx = text["x"] + text["w"] / 2
    cy = text["y"] + text["h"] / 2
    x, y, w, h = box
    return x - PAD <= cx <= x + w + PAD and y - PAD <= cy <= y + h + PAD


def evaluate(pages, keep):
    kept = correct = found = total = 0
    for blocks, boxes in pages:
        chosen = [b for b in blocks if keep(b)]
        kept += len(chosen)
        correct += sum(1 for b in chosen if any(matches(b, box) for box in boxes))
        total += len(boxes)
        found += sum(1 for box in boxes if any(matches(b, box) for b in chosen))
    precision = correct / kept if kept else 0
    recall = found / total if total else 0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0
    return precision, recall, f1, kept


def light_bubble(bg):
    value = int(bg.lstrip("#"), 16)
    r, g, b = (value >> 16) & 255, (value >> 8) & 255, value & 255
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    light = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    chroma = (max(r, g, b) - min(r, g, b)) / 255
    return (light >= 0.65 and chroma <= 0.12) or (light <= 0.02 and chroma <= 0.08)


def main():
    dataset, images_root = sys.argv[1], sys.argv[2]
    truth = load_truth(dataset, images_root)
    pages = []
    for chapter in sorted({c for c, _ in truth}):
        path = os.path.join(OUT_ROOT, chapter, "blocks.json")
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            blocks = json.load(fh)
        by_page = {}
        for block in blocks:
            by_page.setdefault(block["src"], []).append(block)
        for (c, name), boxes in truth.items():
            if c == chapter:
                pages.append((by_page.get(name, []), boxes))
    if not pages:
        raise SystemExit("chưa có blocks.json của chapter OpenMantra nào")

    everything = evaluate(pages, lambda b: True)
    current = evaluate(pages, lambda b: b["kept"])
    print(f"trang: {len(pages)}")
    print("không lọc      P={:.3f} R={:.3f} F1={:.3f} giữ={}".format(*everything))
    print("lọc hiện tại   P={:.3f} R={:.3f} F1={:.3f} giữ={}".format(*current))

    if "--search" in sys.argv:
        results = []
        for fill, poly_fill, enclose in itertools.product(
            [0.55, 0.6, 0.65, 0.68, 0.72, 0.76], [0.3, 0.35, 0.4, 0.45, 0.5, 1.1], [0.0, 0.3, 0.45, 0.6]
        ):
            def keep(b, fill=fill, poly_fill=poly_fill, enclose=enclose):
                if not light_bubble(b["bg"]) or b["enclose"] < enclose:
                    return False
                return b["fill"] >= fill or (b["poly"] and b["fill"] >= poly_fill)
            results.append((evaluate(pages, keep), fill, poly_fill, enclose))
        results.sort(key=lambda item: -item[0][2])
        for (p, r, f1, n), fill, poly_fill, enclose in results[:12]:
            print(f"fill≥{fill} | poly&fill≥{poly_fill} | enclose≥{enclose}: P={p:.3f} R={r:.3f} F1={f1:.3f} giữ={n}")


if __name__ == "__main__":
    main()
