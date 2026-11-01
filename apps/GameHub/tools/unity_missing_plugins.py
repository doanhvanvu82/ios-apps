#!/usr/bin/env python3
"""Chép DLL bên thứ ba còn thiếu từ <game>_Data/Managed vào Assets/Plugins.

AssetRipper không xuất vài thư viện (vd ICSharpCode.SharpZipLib trùng tên với bản đi kèm
Unity) → ILLink báo "Failed to resolve assembly: 'ICSharpCode.SharpZipLib…'" lúc build.
Bỏ qua DLL của engine/Mono/.NET, mã game (Assembly-CSharp*), UniTask (có script riêng: unity_unitask_full.py), DLL đã có trong Assets và
assembly đã được dịch ngược thành mã nguồn trong Assets/Scripts/.

Dùng: unity_missing_plugins.py <ExportedProject> <thư mục game gốc>
"""
import glob
import os
import shutil
import sys

SKIP_PREFIXES = ("UnityEngine.", "UnityEditor.", "Unity.", "System.", "System", "mscorlib", "netstandard",
                 "Mono.", "Assembly-CSharp", "I18N", "Microsoft.", "Accessibility", "Boo.", "UnityScript")


def main():
    project, src = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    base = glob.escape(src)  # tên game có thể chứa [ ] ( )
    managed = glob.glob(os.path.join(base, "*_Data", "Managed")) + glob.glob(os.path.join(base, "*", "*_Data", "Managed"))
    if not managed:
        return
    have = {fn.lower() for _, _, fns in os.walk(os.path.join(project, "Assets")) for fn in fns if fn.lower().endswith(".dll")}
    plugins = os.path.join(project, "Assets", "Plugins")
    copied = []
    for dll in sorted(glob.glob(os.path.join(glob.escape(managed[0]), "*.dll"))):
        name = os.path.basename(dll)
        if name.startswith(SKIP_PREFIXES) or name.startswith("UniTask") or name.lower() in have:
            continue
        # AssetRipper đã dịch ngược assembly này thành mã nguồn (Assets/Scripts/<tên>/) → thêm DLL sẽ trùng kiểu.
        if os.path.isdir(os.path.join(project, "Assets", "Scripts", os.path.splitext(name)[0])):
            continue
        os.makedirs(plugins, exist_ok=True)
        shutil.copy2(dll, os.path.join(plugins, name))
        copied.append(name)
    if copied:
        print(f"✅ Plugins thiếu: chép {len(copied)} DLL từ Managed/ ({', '.join(copied)})")


if __name__ == "__main__":
    main()
