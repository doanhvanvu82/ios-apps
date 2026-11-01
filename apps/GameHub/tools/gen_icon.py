#!/usr/bin/env python3
"""Vẽ icon GameHub (đen + gradient tím-xanh + gamepad trắng) bằng Pillow.

Sinh ra:
  tools/icon_gen/AppIcon1024.png     (App Store)
  tools/icon_gen/AppIcon60x60@2x.png (iPhone 120x120)
  tools/icon_gen/AppIcon76x76@2x~ipad.png (iPad 152x152)
"""
from PIL import Image, ImageDraw
import os
import sys

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon_gen")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1024


def rounded_rect_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    # iOS 7+ superellipse xấp xỉ = bo góc ~22.5% — dùng đủ cho hiển thị.
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def make_base(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # Gradient dọc: đen (trên) → tím đậm (giữa) → xanh cyan (dưới).
    top = (18, 16, 30)
    mid = (76, 40, 140)
    bot = (40, 170, 220)
    for y in range(size):
        t = y / (size - 1)
        if t < 0.55:
            k = t / 0.55
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.55) / 0.45
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * k) for i in range(3))
        d.line([(0, y), (size, y)], fill=c + (255,))
    return img


def draw_gamepad(d, s, color=(255, 255, 255), alpha=255):
    """Vẽ gamepad đơn giản: 2 tay cầm tròn + thân + d-pad + 4 nút."""
    w = s  # chiều ngang của gamepad
    h = s * 0.62
    x0 = (SIZE - w) / 2
    y0 = (SIZE - h) / 2
    r = h / 2  # bán kính 2 tay cầm
    fill = color + (alpha,)

    # Thân giữa (rounded rect)
    body_h = h * 0.58
    d.rounded_rectangle(
        [x0 + r * 0.5, y0 + (h - body_h) / 2, x0 + w - r * 0.5, y0 + (h + body_h) / 2],
        radius=body_h / 3, fill=fill)
    # Tay cầm trái + phải (đĩa tròn)
    d.ellipse([x0, y0 + h * 0.12, x0 + 2 * r, y0 + h * 0.12 + 2 * r], fill=fill)
    d.ellipse([x0 + w - 2 * r, y0 + h * 0.12, x0 + w, y0 + h * 0.12 + 2 * r], fill=fill)

    # D-pad (trái): chữ thập
    cx = x0 + r
    cy = y0 + h * 0.12 + r
    arm = r * 0.62
    thick = r * 0.42
    d.rounded_rectangle([cx - thick / 2, cy - arm, cx + thick / 2, cy + arm],
                        radius=thick / 4, fill=(18, 16, 30, 255))
    d.rounded_rectangle([cx - arm, cy - thick / 2, cx + arm, cy + thick / 2],
                        radius=thick / 4, fill=(18, 16, 30, 255))

    # 4 nút (phải): kim cương
    bx = x0 + w - r
    by = y0 + h * 0.12 + r
    br = r * 0.17
    gap = r * 0.42
    for dx, dy in [(-gap, 0), (gap, 0), (0, -gap), (0, gap)]:
        d.ellipse([bx + dx - br, by + dy - br, bx + dx + br, by + dy + br],
                  fill=(18, 16, 30, 255))

    # 2 nút nhỏ giữa (start/select)
    mx = x0 + w / 2
    my = y0 + h * 0.12 + r
    for dx in (-gap * 1.15, gap * 1.15):
        d.rounded_rectangle(
            [mx + dx - r * 0.16, my + r * 0.28, mx + dx + r * 0.16, my + r * 0.40],
            radius=r * 0.08, fill=(18, 16, 30, 255))


def export(img, name, size):
    out = img.resize((size, size), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    out.save(path)
    print(f"✅ {path} ({size}x{size})")


def main():
    base = make_base(SIZE)
    draw_gamepad(ImageDraw.Draw(base), SIZE * 0.68)
    # iOS tự bo góc — giữ icon vuông đầy.
    export(base, "AppIcon1024.png", 1024)
    export(base, "AppIcon60x60@2x.png", 120)
    export(base, "AppIcon76x76@2x~ipad.png", 152)
    print("Xong:", OUT_DIR)


if __name__ == "__main__":
    sys.exit(main())
