#!/usr/bin/env python3
"""
Dọn file .cs trùng do AssetRipper sinh ra.

Vấn đề:
    Khi AssetRipper export game có **cả** DLL Mono lẫn metadata IL2CPP, nó có
    thể sinh ra một file "dummy" cho các type mà nó không tìm thấy, ĐỒNG THỜI
    vẫn export file thật chứa cùng class. Khi 2 file chỉ khác nhau ở **hoa/thường**
    (`CgViewer.cs` vs `CGViewer.cs`), Unity trên Linux coi chúng là trùng nhau →
    class bị "mất" → `error CS0246: The type or namespace name 'X' could not be found`.

Cách sửa:
    - Tìm file chứa marker dummy của AssetRipper:
        "Dummy class. This could have happened for several reasons"
    - Nếu có file khác cùng tên (khác hoa/thường) chứa code thật → xoá file dummy.
    - Nếu không có → giữ lại (dummy là thứ duy nhất còn).

Cách dùng:
    python3 tools/unity_fix_duplicate_types.py <project-dir> [--apply]
"""
import os
import shutil
import sys

DUMMY_MARK = "Dummy class. This could have happened for several reasons"
APPLY = "--apply" in sys.argv


def find_dummies(project):
    """→ [(dummy_path, real_path_or_None)]"""
    by_lower = {}
    for dp, dn, fn in os.walk(project):
        if "Library" in dp or "Temp" in dp or "obj" in dp:
            dn[:] = []
            continue
        for f in fn:
            if not f.endswith(".cs"):
                continue
            p = os.path.join(dp, f)
            by_lower.setdefault(f.lower(), []).append(p)

    out = []
    for lower, paths in by_lower.items():
        if len(paths) < 2:
            continue
        dummies = []
        for p in paths:
            try:
                with open(p, encoding="utf-8", errors="ignore") as fh:
                    if DUMMY_MARK in fh.read():
                        dummies.append(p)
            except OSError:
                pass
        for d in dummies:
            real = None
            for p in paths:
                if p == d:
                    continue
                try:
                    with open(p, encoding="utf-8", errors="ignore") as fh:
                        if DUMMY_MARK not in fh.read():
                            real = p
                            break
                except OSError:
                    pass
            out.append((d, real))
    return out


def main():
    if len(sys.argv) < 2:
        print("Usage: unity_fix_duplicate_types.py <project-dir> [--apply]")
        return 1
    project = os.path.abspath(sys.argv[1])
    if not os.path.isdir(project):
        print(f"❌ Không thấy {project}")
        return 1

    dummies = find_dummies(project)
    if not dummies:
        print("✅ Không có file dummy trùng — không cần sửa.")
        return 0

    print(f"Tìm thấy {len(dummies)} file dummy trùng:\n")
    removed = 0
    for d, real in dummies:
        print(f"  dummy: {os.path.relpath(d, project)}")
        if real:
            print(f"  thật : {os.path.relpath(real, project)}")
        else:
            print("  ⚠️  Không tìm thấy bản thật → giữ lại dummy")
        print()

        if not APPLY:
            continue
        if not real:
            continue
        for target in (d, d + ".meta"):
            if os.path.isfile(target):
                os.remove(target)
                removed += 1
        print(f"  ✅ Đã xoá {os.path.basename(d)} (+ .meta)")

    if APPLY:
        print(f"\n✅ Đã xoá {removed} file")
    else:
        print("(Chạy lại với --apply để xoá)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
