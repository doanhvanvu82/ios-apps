#!/usr/bin/env python3
"""Vá mã game để chạy được trên WebGL (sửa bằng text trên mã C# đã dịch ngược).

1. SteamManager gọi Application.Quit() khi không tải được steam_api → game thoát ngay
   lúc khởi động. Trên web không có Steam: bỏ lệnh Quit, game chạy tiếp (Initialized=false).
2. Application.dataPath trên WebGL là URL của trang ("http://…") → ghép làm đường dẫn file
   ra "/http:/…" → DirectoryNotFoundException khi lưu. Dùng persistentDataPath (IndexedDB).

Dùng: unity_webgl_runtime_fixes.py <thư-mục-project>   (chỉ sửa mã game: Assets/Scripts, Assets/Plugins)
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
steam = data_path = 0
for base in (root / "Assets" / "Scripts", root / "Assets" / "Plugins"):
    for cs in base.rglob("*.cs") if base.is_dir() else []:
        text = cs.read_text(encoding="utf-8-sig", errors="replace")
        new = text
        if cs.name.startswith("SteamManager"):
            new, n = re.subn(r"\bApplication\.Quit\(\);", "/* web: không có Steam */;", new)
            steam += n
        new, n = re.subn(r"\bApplication\.dataPath\b", "Application.persistentDataPath", new)
        data_path += n
        if new != text:
            cs.write_text(new, encoding="utf-8")
print(f"[GameHub] runtime fixes: SteamManager Quit bỏ {steam}, dataPath→persistentDataPath {data_path}")
