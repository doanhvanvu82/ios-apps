#!/usr/bin/env python3
"""Vẽ icon 1024×1024 cho MyDrive (placeholder — thay icon đẹp sau bằng cách
ghi đè tools/icon_gen/AppIcon1024.png)."""
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "icon_gen")
SIZE = 1024


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.new("RGB", (SIZE, SIZE), "#1a73e8")
    d = ImageDraw.Draw(img)

    # Nền gradient giả lập bằng các dải màu dọc.
    top = (26, 115, 232)     # xanh Google Drive
    bottom = (11, 61, 145)
    for y in range(SIZE):
        t = y / SIZE
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (SIZE, y)], fill=color)

    # Tam giác Drive 3 màu (logo cách điệu, vẽ bằng polygon).
    cx, cy = SIZE / 2, SIZE / 2
    s = SIZE * 0.34          # nửa cạnh
    h = s * 0.866            # chiều cao tam giác đều
    # 3 tam giác con quanh tâm
    blue = (66, 133, 244)
    green = (52, 168, 83)
    yellow = (251, 188, 5)
    white = (255, 255, 255)
    lw = SIZE * 0.012

    def tri(p1, p2, p3, fill):
        d.polygon([p1, p2, p3], fill=fill)

    # Khung tam giác lớn nghiêng (kiểu logo Drive): 3 cạnh màu khác nhau.
    a = (cx, cy - h * 0.62)
    b = (cx - s * 0.72, cy + h * 0.42)
    c = (cx + s * 0.72, cy + h * 0.42)
    tri(a, b, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), yellow)
    tri(b, c, (cx, cy + h * 0.08), green)
    tri(c, a, ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2), blue)
    # Lõi trắng mờ ở giữa gợi "đám mây/đồng bộ".
    d.ellipse(
        [cx - s * 0.30, cy - s * 0.10, cx + s * 0.30, cy + s * 0.46],
        fill=white,
        outline=None,
    )
    d.ellipse(
        [cx - s * 0.30 - lw, cy - s * 0.10 - lw, cx + s * 0.30 + lw, cy + s * 0.46 + lw],
        outline=white,
        width=int(lw * 2),
    )

    img.save(os.path.join(OUT, "AppIcon1024.png"))
    print(f"→ Đã vẽ {OUT}/AppIcon1024.png ({SIZE}×{SIZE})")


if __name__ == "__main__":
    main()
