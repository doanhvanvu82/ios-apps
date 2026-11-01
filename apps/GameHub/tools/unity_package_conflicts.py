#!/usr/bin/env python3
"""Gỡ xung đột tên giữa mã/DLL của game và các gói Unity 6 tự thêm vào.

    unity_package_conflicts.py <project-dir>

1. `com.unity.multiplayer.center`: gói chỉ dùng trong editor mà Unity 6 tự thêm.
   Game có namespace `Editor` → gói báo CS0118 "'Editor' is a namespace but is
   used like a type". Bản build không cần gói này → bỏ khỏi manifest.
2. `Unity.Mathematics.Extensions*.dll` (Entities/DOTS đời cũ) định nghĩa
   `Unity.Mathematics.AABB`; Unity tự tham chiếu DLL dựng sẵn cho mọi assembly
   nên `com.unity.rendering.light-transport` (phụ thuộc của URP 17) báo CS0104
   'AABB' mơ hồ với RadeonRays.AABB. Nếu script game không dùng kiểu của DLL này
   → đặt `isExplicitlyReferenced: 1` (DLL khác vẫn liên kết với nó khi chạy).
3. DLL của mod PC (BepInEx, Harmony, MonoMod, XUnity.AutoTranslator…) mà AssetRipper
   kéo vào từ thư mục game: vô dụng trên WebGL, còn gây trùng tên — vd
   Common.ExtProtocol.dll khai báo namespace gốc `Common`, che
   Unity.Burst.Intrinsics.Common → com.unity.collections báo CS0234 'umul128'.
   Bỏ ra PatchBackup/ nếu script game không dùng namespace của chúng.
4. `Unity.InternalAPIEngineBridge.NNN.dll` không DLL nào tham chiếu (sót lại từ gói
   cũ): bản 002 khai báo namespace `Unity.Editor.Bridge` → `Editor` trong gói
   multiplayer.center thành namespace (CS0118). Bỏ ra PatchBackup/.
"""
import shutil
import json
import os
import re
import sys

EDITOR_ONLY_PACKAGES = ("com.unity.multiplayer.center",)
LEGACY_MATH_DLL = re.compile(r"^Unity\.Mathematics\.Extensions(\.Hybrid)?\.dll$")
LEGACY_MATH_TYPES = re.compile(r"\b(AABB|MinMaxAABB|Unity\.Mathematics\.Extensions)\b")
MOD_DLL = re.compile(
    r"^(0Harmony\w*|BepInEx[\w.]*|HarmonyX\w*|MonoMod[\w.]*|XUnity[\w.]*|ExIni|[\w.]*\.ExtProtocol"
    r"|(Baidu|Bing|Custom|DeepL|Google|LingoCloud|Papago|Watson|Yandex)Translate\w*|LecPowerTranslator\d*|ezTransXP)\.dll$")
BRIDGE_DLL = re.compile(r"^Unity\.InternalAPIEngineBridge\.\d+\.dll$")
MOD_NAMESPACES = re.compile(r"\b(BepInEx|HarmonyLib|MonoMod|XUnity)\b")


def scripts_use_legacy_math(project):
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            if fn.endswith(".cs"):
                try:
                    if LEGACY_MATH_TYPES.search(open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()):
                        return True
                except OSError:
                    pass
    return False


def scripts_match(project, pattern):
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            if fn.endswith(".cs"):
                try:
                    if pattern.search(open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()):
                        return True
                except OSError:
                    pass
    return False


def drop_mod_dlls(project):
    mods = []
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        mods += [os.path.join(dp, fn) for fn in fns if MOD_DLL.match(fn)]
    if not mods or scripts_match(project, MOD_NAMESPACES):
        return
    backup = os.path.join(project, "PatchBackup", "mod-dlls")
    os.makedirs(backup, exist_ok=True)
    for dll in mods:
        for path in (dll, dll + ".meta"):
            if os.path.exists(path):
                shutil.move(path, os.path.join(backup, os.path.basename(path)))
    print(f"✅ Bỏ {len(mods)} DLL mod PC (BepInEx/Harmony/XUnity…) — không dùng được trên WebGL")


def drop_unused_bridges(project):
    dlls = [os.path.join(dp, fn) for dp, _, fns in os.walk(os.path.join(project, "Assets"))
            for fn in fns if fn.endswith(".dll")]
    bridges = [d for d in dlls if BRIDGE_DLL.match(os.path.basename(d))]
    if not bridges:
        return
    blobs = {d: open(d, "rb").read() for d in dlls}
    backup = os.path.join(project, "PatchBackup", "unused-bridges")
    for bridge in bridges:
        name = os.path.basename(bridge)[:-4].encode() + b"\0"
        if any(name in blob for d, blob in blobs.items() if d != bridge):
            continue
        os.makedirs(backup, exist_ok=True)
        for path in (bridge, bridge + ".meta"):
            if os.path.exists(path):
                shutil.move(path, os.path.join(backup, os.path.basename(path)))
        print(f"✅ Bỏ {os.path.basename(bridge)}: không DLL nào dùng, gây trùng namespace Unity.Editor")


def main():
    project = os.path.abspath(sys.argv[1])
    manifest_path = os.path.join(project, "Packages", "manifest.json")
    try:
        manifest = json.load(open(manifest_path))
    except (OSError, ValueError):
        manifest = None
    if manifest:
        deps = manifest.get("dependencies", {})
        removed = [p for p in EDITOR_ONLY_PACKAGES if deps.pop(p, None) is not None]
        if removed:
            json.dump(manifest, open(manifest_path, "w"), indent=2)
            print("✅ Bỏ gói chỉ dùng trong editor: " + ", ".join(removed))

    drop_mod_dlls(project)
    drop_unused_bridges(project)

    metas = []
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        metas += [os.path.join(dp, fn + ".meta") for fn in fns if LEGACY_MATH_DLL.match(fn)]
    metas = [m for m in metas if os.path.isfile(m)]
    if metas and not scripts_use_legacy_math(project):
        for meta in metas:
            text = open(meta, encoding="utf-8").read()
            new = re.sub(r"^(\s*isExplicitlyReferenced:) 0$", r"\1 1", text, flags=re.M)
            if new != text:
                open(meta, "w", encoding="utf-8").write(new)
                print(f"✅ {os.path.basename(meta)[:-5]}: chỉ tham chiếu tường minh (tránh AABB trùng với URP 17)")


if __name__ == "__main__":
    main()
