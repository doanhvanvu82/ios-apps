#!/usr/bin/env python3
"""Đặt ASTC làm định dạng nén texture mặc định cho WebGL trong ProjectSettings.

Đặt `EditorUserBuildSettings.webGLBuildSubtarget = ASTC` lúc build thì texture
đã import (DXT) phải import lại toàn bộ (~8 phút/game). Ghi sẵn vào
ProjectSettings trước lần mở Unity đầu tiên thì import một lần ra ASTC luôn.
Định dạng `m_Format: 3` (= ASTC) giống template Unity 6 cho Android; Unity tự
nâng lên định dạng mới khi đọc.

Cách dùng: python3 unity_astc_default.py <project>
"""
import os
import re
import sys

KEY = "  m_BuildTargetDefaultTextureCompressionFormat:"
ENTRY = "\n  - m_BuildTarget: WebGL\n    m_Format: 3"


def main(project):
    path = os.path.join(project, "ProjectSettings", "ProjectSettings.asset")
    text = open(path, encoding="utf-8").read()
    if KEY not in text:
        print("⚠️  ProjectSettings không có m_BuildTargetDefaultTextureCompressionFormat — để C# đặt subtarget")
        return
    # Khối danh sách: các dòng sau KEY bắt đầu bằng "  - " hoặc thụt sâu hơn.
    block = re.search(re.escape(KEY) + r"( \[\])?((?:\n  [- ] .*)*)", text)
    items = block.group(2)
    if "m_BuildTarget: WebGL" in items:
        print("✅ ASTC/WebGL: ProjectSettings đã có định dạng riêng cho WebGL — giữ nguyên")
        return
    if "m_Formats" in items:
        print("⚠️  ProjectSettings dùng định dạng m_Formats mới — để C# đặt subtarget")
        return
    text = text[:block.start()] + KEY + ENTRY + items + text[block.end():]
    tmp = path + ".tmp"
    open(tmp, "w", encoding="utf-8").write(text)
    os.replace(tmp, path)
    print("✅ ASTC/WebGL: đã đặt định dạng texture mặc định trong ProjectSettings")


if __name__ == "__main__":
    main(sys.argv[1])
