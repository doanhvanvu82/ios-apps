#!/usr/bin/env python3
"""CanvasScaler "Scale With Screen Size" khớp theo chiều rộng → UI tràn trên/dưới ở màn rộng.

iPhone ngang (vd 932x430, tỉ lệ ~2.17) rộng hơn tham chiếu 16:9: Match Width làm UI cao hơn
màn hình. Đổi mọi CanvasScaler m_UiScaleMode 1 + m_ScreenMatchMode 0 + m_MatchWidthOrHeight 0
sang Expand (m_ScreenMatchMode 1) để UI luôn nằm gọn trong màn hình.

Dùng: unity_canvas_expand.py <ExportedProject>
"""
import os
import re
import sys

ASSET_EXT = (".unity", ".prefab")
SCALER = re.compile(
    r"(  m_UiScaleMode: 1\n(?:  [^\n]*\n)*?  m_ScreenMatchMode: )0(\n  m_MatchWidthOrHeight: 0\n)"
)


def main():
    assets = os.path.join(os.path.abspath(sys.argv[1]), "Assets")
    fixed = 0
    for dp, _, fns in os.walk(assets):
        for fn in fns:
            if not fn.endswith(ASSET_EXT):
                continue
            path = os.path.join(dp, fn)
            text = open(path, encoding="utf-8", errors="ignore").read()
            if "m_UiScaleMode: 1" not in text:
                continue
            new, n = SCALER.subn(r"\g<1>1\g<2>", text)
            if n:
                open(path + ".tmp", "w", encoding="utf-8").write(new)
                os.replace(path + ".tmp", path)
                fixed += n
    if fixed:
        print(f"✅ CanvasScaler: đổi {fixed} scaler sang Expand (UI không tràn màn hình rộng)")


if __name__ == "__main__":
    main()
