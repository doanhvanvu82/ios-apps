#!/usr/bin/env python3
"""Sinh trang xem trước cho kết quả của render_test.py.

Quét một thư mục gốc, mỗi thư mục con là một chương; mỗi trang có `<tên>.before.png`
(chỉ xoá chữ gốc) và `<tên>.after.png` (đã dán bản dịch) cạnh nhau. Mở index.html
bằng trình duyệt là xem được, không cần iPhone.

    python3 tools/review_index.py .state/mangalate-review
"""

import html
import json
import os
import sys


def collect(root):
    chapters = []
    for name in sorted(os.listdir(root)):
        folder = os.path.join(root, name)
        if not os.path.isdir(folder):
            continue
        pages = []
        for entry in sorted(os.listdir(folder)):
            if not entry.endswith(".after.png"):
                continue
            stem = entry[: -len(".after.png")]
            before = os.path.join(folder, stem + ".before.png")
            meta = os.path.join(folder, stem + ".json")
            blocks = []
            if os.path.exists(meta):
                with open(meta, encoding="utf-8") as handle:
                    blocks = json.load(handle).get("blocks") or []
            pages.append(
                {
                    "stem": stem,
                    "before": os.path.relpath(before, root) if os.path.exists(before) else None,
                    "after": os.path.relpath(os.path.join(folder, entry), root),
                    "blocks": len(blocks),
                    "translated": sum(1 for b in blocks if b.get("translation")),
                }
            )
        if pages:
            chapters.append({"name": name, "pages": pages})
    return chapters


def render_index(root, chapters):
    total = sum(len(c["pages"]) for c in chapters)
    parts = [
        "<!doctype html>",
        '<html lang="vi"><head><meta charset="utf-8">',
        "<title>Mangalate — kết quả dịch</title>",
        "<style>",
        "body{font:14px/1.5 system-ui,sans-serif;margin:24px;background:#111;color:#eee}",
        "h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:32px 0 12px;",
        "border-bottom:1px solid #333;padding-bottom:6px}",
        ".meta{color:#999;margin-bottom:16px}",
        ".page{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:28px}",
        ".page figure{margin:0}.page figcaption{color:#aaa;font-size:12px;margin-bottom:4px}",
        ".page img{width:100%;height:auto;border-radius:4px;background:#222;display:block}",
        "a{color:#7cc4ff}",
        "</style></head><body>",
        f"<h1>Mangalate — kết quả dịch ({total} trang)</h1>",
        '<div class="meta">Trái: ảnh gốc. Phải: đã dán bản dịch. '
        'Bấm ảnh để mở bản đầy đủ.</div>',
    ]
    for chapter in chapters:
        parts.append(f"<h2>{html.escape(chapter['name'])} — {len(chapter['pages'])} trang</h2>")
        for page in chapter["pages"]:
            parts.append('<div class="page">')
            for label, path in (("Before", page["before"]), ("After", page["after"])):
                if not path:
                    continue
                parts.append(
                    f'<figure><figcaption>{label} — {page["translated"]}/{page["blocks"]} block '
                    f'dịch</figcaption><a href="{html.escape(path)}">'
                    f'<img loading="lazy" src="{html.escape(path)}" alt="{label}"></a></figure>'
                )
            parts.append("</div>")
    parts.append("</body></html>")
    with open(os.path.join(root, "index.html"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else ".state/mangalate-review"
    chapters = collect(root)
    render_index(root, chapters)
    total = sum(len(c["pages"]) for c in chapters)
    print(f"{os.path.join(root, 'index.html')} — {len(chapters)} chương, {total} trang")


if __name__ == "__main__":
    main()
