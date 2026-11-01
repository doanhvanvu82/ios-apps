#!/usr/bin/env python3
"""
Chuyển game Unity IL2CPP → dạng Mono để AssetRipper decompile được.

Vì sao?
    Game Unity build bằng **IL2CPP** đóng gói logic C# vào `GameAssembly.dll`
    (native x86-64) → không decompile được.

    Nhưng nhiều game **vô tình để lại bản Mono gốc** trong game:
      • `*_Data/Managed/Assembly-CSharp.dll`  (dev build Mono rồi đổi sang IL2CPP)
      • `BepInEx_BackUpThisFolder/` hay `*_BackUpThisFolder_ButDontShipItWithYourGame/`
        (thư mục backup do dev để lại)
      • `il2cppOutput/` (C++ sinh từ IL2CPP — không dùng được)

    Bản Mono đó **có IL thật** → AssetRipper decompile ra source C# → build WebGL được.

Cách dùng:
    python3 tools/unity_il2cpp_to_mono.py <game-dir> [--out <dir>]
"""
import os
import re
import shutil
import sys

APPLY = "--apply" in sys.argv


def find_managed_dir(game):
    """Tìm thư mục `Managed` chứa Assembly-CSharp.dll gốc (không phải BepInEx interop)."""
    cands = []
    for dp, dn, fn in os.walk(game):
        depth = dp.count(os.sep) - game.count(os.sep)
        if depth > 4:
            dn[:] = []
            continue
        if os.path.basename(dp) != "Managed":
            continue
        acs = os.path.join(dp, "Assembly-CSharp.dll")
        if not os.path.isfile(acs):
            continue
        # BepInEx interop là proxy (AssemblyRef tới Il2CppInterop.Runtime) → bỏ
        if "BepInEx" in dp or "interop" in dp.lower():
            continue
        cands.append((dp, os.path.getsize(acs)))
    if not cands:
        return None
    # Ưu tiên thư mục có nhiều DLL nhất
    cands.sort(key=lambda x: len(os.listdir(x[0])), reverse=True)
    return cands[0][0]


def is_interop_proxy(dll):
    """BepInEx/Il2CppInterop sinh proxy → method body rỗng, không decompile được logic."""
    try:
        with open(dll, "rb") as f:
            head = f.read(4096)
    except OSError:
        return True
    # AssemblyRef "Il2CppInterop.Runtime" nằm trong bảng AssemblyRef
    return b"Il2CppInterop" in head or b"Il2Cppmscorlib" in head


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
        print("Usage: unity_il2cpp_to_mono.py <game-dir> [--out <dir>]")
        return 1
    game = os.path.abspath(sys.argv[1])
    if not os.path.isdir(game):
        print(f"❌ Không thấy {game}")
        return 1

    out = game
    if "--out" in sys.argv:
        out = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])

    print(f"→ Game: {game}")
    managed = find_managed_dir(game)
    if not managed:
        print("❌ Không tìm thấy thư mục Managed/Assembly-CSharp.dll gốc (Mono).")
        print("   Game này không giữ lại bản Mono → không chuyển đổi được.")
        return 2

    n_dll = len([f for f in os.listdir(managed) if f.endswith(".dll")])
    print(f"→ Managed: {managed}  ({n_dll} DLL)")

    acs = os.path.join(managed, "Assembly-CSharp.dll")
    if is_interop_proxy(acs):
        print("❌ Assembly-CSharp.dll là BepInEx interop proxy (không có IL logic).")
        return 3
    print("✅ Assembly-CSharp.dll có IL thật (không phải proxy)")

    # --- Tìm thư mục Data của game ---
    data_dir = None
    for d in sorted(os.listdir(game)):
        p = os.path.join(game, d)
        if os.path.isdir(p) and d.endswith("_Data"):
            data_dir = p
            break
    if not data_dir:
        print("❌ Không tìm thấy thư mục *_Data")
        return 4
    print(f"→ Data   : {data_dir}")

    ga = os.path.join(game, "GameAssembly.dll")
    print(f"→ GameAssembly.dll: {'có' if os.path.isfile(ga) else 'không'}")

    if not APPLY:
        print("\n(Chạy lại với --apply để tạo bản Mono)")
        return 0

    # --- Tạo bản Mono ---
    if os.path.abspath(out) == os.path.abspath(game):
        print("❌ Không ghi đè lên bản gốc — dùng --out <dir>")
        return 1
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out, exist_ok=True)

    # 1) copy toàn bộ game (bỏ GameAssembly + il2cpp_output + BepInEx)
    print("→ Copy game (loại GameAssembly.dll, il2cpp_output, BepInEx)…")
    for item in os.listdir(game):
        src = os.path.join(game, item)
        dst = os.path.join(out, item)
        if item in ("GameAssembly.dll", "il2cpp_output", "il2cpp_data"):
            continue
        if item.startswith("BepInEx") or "BepInEx" in item:
            continue
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
        else:
            shutil.copy2(src, dst)

    # 2) chép Managed/ vào <Data>/Managed/
    dest_managed = os.path.join(out, os.path.basename(data_dir), "Managed")
    os.makedirs(dest_managed, exist_ok=True)
    copied = 0
    for f in os.listdir(managed):
        if f.endswith(".dll"):
            shutil.copy2(os.path.join(managed, f), os.path.join(dest_managed, f))
            copied += 1
    print(f"→ Đã chép {copied} DLL vào {os.path.relpath(dest_managed, out)}/")

    # 3) xoá dấu vết IL2CPP
    for junk in ("il2cpp_data", "il2cpp_output"):
        p = os.path.join(out, os.path.basename(data_dir), junk)
        if os.path.isdir(p):
            shutil.rmtree(p)
    for extra in list(os.listdir(out)):
        if extra.startswith("BepInEx") or "il2cpp_output" in extra:
            p = os.path.join(out, extra)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)

    print(f"\n✅ Bản Mono: {out}")
    print("   Bước tiếp theo: chạy tools/unity_extract.sh trên thư mục này")
    return 0


if __name__ == "__main__":
    sys.exit(main())
