#!/usr/bin/env python3
"""
Chuẩn hoá project Unity export để build được bằng Unity 6000.

AssetRipper export **DLL** của các package (URP / SRP Core / ShaderGraph) vào
`Assets/Plugins/`, kèm **source** của TextMeshPro. Hai vấn đề:

1. **DLL SRP cũ** (URP 12 của Unity 2021.3) → IL2CPP của Unity 6 không resolve
   được field đã bị đổi tên:
       Unresolved field reference : …RendererUtils.RendererList::nullRendererList
   → xoá DLL, dùng package `com.unity.render-pipelines.*` bản 17.x (đi kèm editor).

2. **Source TMP trùng với DLL TMP** → `CS0121: The call is ambiguous between
   'TMPro.TMPro_ExtensionMethod…'` → xoá source TMP (giữ DLL).

Cách dùng:
    python3 tools/unity_normalize_project.py <project-dir> [--apply]
"""
import json
import os
import shutil
import sys

PROJECT = sys.argv[1]
APPLY = "--apply" in sys.argv
PLUGINS = os.path.join(PROJECT, "Assets", "Plugins")
MANIFEST = os.path.join(PROJECT, "Packages", "manifest.json")
BACKUP = os.path.join(PROJECT, "PatchBackup")

# DLL của render pipeline → thay bằng package
SRP_DLLS = [
    "Unity.RenderPipelines.Core.Runtime.dll",
    "Unity.RenderPipelines.Core.Runtime.Shared.dll",
    "Unity.RenderPipelines.Core.ShaderLibrary.dll",
    "Unity.RenderPipelines.Universal.Runtime.dll",
    "Unity.RenderPipelines.Universal.ShaderLibrary.dll",
    "Unity.RenderPipelines.Universal.Shaders.dll",
    "Unity.RenderPipelines.Universal.2D.Runtime.dll",
    "Unity.RenderPipelines.Universal.Config.Runtime.dll",
    "Unity.RenderPipelines.Universal.ShaderLibrary.dll",
    "Unity.RenderPipelines.GPUDriven.Runtime.dll",
    "Unity.RenderPipeline.Universal.ShaderLibrary.dll",
    "Unity.InternalAPIEngineBridge.001.dll",
    # SRP Core đi kèm các package này → xoá để tránh CS1704 trùng tên
    "Unity.Mathematics.dll",
    "Unity.Burst.dll",
    "Unity.Burst.Unsafe.dll",
    "Unity.Collections.dll",
    "Unity.Collections.LowLevel.ILSupport.dll",
    # TextMeshPro: Unity 6 đã gộp TMP vào package `com.unity.ugui`.
    # Giữ cả DLL TMP của game → trùng type `TMPro.TMPro_ExtensionMethods`
    # với package → CS0121 "The call is ambiguous".
    "Unity.TextMeshPro.dll",
    # UI (uGUI) của game cũng trùng với com.unity.ugui
    "UnityEngine.UI.dll",
]

PACKAGES = {
    "com.unity.render-pipelines.universal": "17.0.4",
    "com.unity.render-pipelines.core": "17.0.4",
    "com.unity.shadergraph": "17.0.4",
}
# KHÔNG khai báo mathematics/burst/collections: chúng là dependency của
# render-pipelines.core → khai báo thêm sẽ gây CS1704 (trùng tên assembly).

# Thư mục source TMP do AssetRipper export (trùng với Unity.TextMeshPro.dll)
TMP_SRC_DIRS = [
    os.path.join(PROJECT, "Assets", "Scripts", "Assembly-CSharp", "TMPro"),
    os.path.join(PROJECT, "Assets", "Scripts", "Assembly-CSharp", "TMPro_ExtensionMethods"),
]

if not APPLY:
    print("→ Chế độ xem trước (thêm --apply để thực thi)\n")

# --- DLL sẽ xoá ---
# Unity.2D.*.dll của game (2D Animation/Common) tham chiếu bridge này; nó không có trong package SRP.
BRIDGE = "Unity.InternalAPIEngineBridge.001.dll"
HAS_2D = os.path.isdir(PLUGINS) and any(f.startswith("Unity.2D.") and f.endswith(".dll") for f in os.listdir(PLUGINS))
if HAS_2D:
    SRP_DLLS.remove(BRIDGE)
dlls = [f for f in SRP_DLLS if os.path.isfile(os.path.join(PLUGINS, f))]
print(f"DLL sẽ xoá ({len(dlls)}):")
for f in dlls:
    print(f"    - {f}")

# --- Source TMP ---
tmp_dirs = [d for d in TMP_SRC_DIRS if os.path.isdir(d)]
print(f"\nThư mục source TMP sẽ xoá ({len(tmp_dirs)}):")
for d in tmp_dirs:
    n = sum(len(f) for _, _, f in os.walk(d))
    print(f"    - {os.path.relpath(d, PROJECT)} ({n} file)")

# --- Manifest ---
manifest = {}
if os.path.isfile(MANIFEST):
    with open(MANIFEST) as fh:
        manifest = json.load(fh)
deps = manifest.setdefault("dependencies", {})

print("\nPackage sẽ thêm/cập nhật:")
for pkg, ver in PACKAGES.items():
    cur = deps.get(pkg)
    print(f"    {pkg}: {cur or '(chưa có)'} → {ver}")

if not APPLY:
    sys.exit(0)

# --- Thực thi ---
os.makedirs(BACKUP, exist_ok=True)

for f in dlls:
    src = os.path.join(PLUGINS, f)
    dst = os.path.join(BACKUP, f)
    if not os.path.exists(dst):
        shutil.copy2(src, dst)
    for target in (src, src + ".meta"):
        if os.path.isfile(target):
            os.remove(target)

# Project đã chuẩn hoá trước khi có luật giữ bridge: DLL nằm trong PatchBackup → trả lại,
# không thì ILLink báo "Failed to resolve assembly 'Unity.InternalAPIEngineBridge.001'".
if HAS_2D and not os.path.isfile(os.path.join(PLUGINS, BRIDGE)) and os.path.isfile(os.path.join(BACKUP, BRIDGE)):
    shutil.copy2(os.path.join(BACKUP, BRIDGE), os.path.join(PLUGINS, BRIDGE))
    print(f"↩ Trả lại {BRIDGE} (Unity.2D.*.dll của game cần nó)")

for d in tmp_dirs:
    dst = os.path.join(BACKUP, "src_" + os.path.basename(d))
    if not os.path.exists(dst):
        shutil.copytree(d, dst)
    shutil.rmtree(d)

for pkg, ver in PACKAGES.items():
    deps[pkg] = ver

with open(MANIFEST, "w") as fh:
    json.dump(manifest, fh, indent=2)

# csc.rsp: nâng C# lên latest (code decompile dùng tính năng C# 10+)
rsp = os.path.join(PROJECT, "Assets", "csc.rsp")
if not os.path.isfile(rsp):
    with open(rsp, "w") as fh:
        fh.write("-langversion:latest\n")

print(f"\n✅ Đã chuẩn hoá project (backup tại {os.path.relpath(BACKUP, PROJECT)}/)")
