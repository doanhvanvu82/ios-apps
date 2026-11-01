#!/usr/bin/env python3
"""
Thay các DLL "engine/package" trong project Unity export bằng package thật.

Vì sao cần:
    AssetRipper export **DLL** của các package (URP, TMP, 2D Sprite, Mathematics,
    Burst…) vào `Assets/Plugins/`. Nhưng DLL đó được build cho version Unity cũ
    (ví dụ URP 12 của Unity 2021.3) → IL2CPP của Unity 6 không resolve được
    (lỗi `Unresolved field reference: …RendererList::nullRendererList`).

    Cách đúng: **xoá DLL**, và khai báo package tương ứng trong
    `Packages/manifest.json` để Unity tự resolve bản đúng version.

Cách dùng:
    python3 tools/unity_use_packages.py <project-dir> [--apply]
"""
import json
import os
import re
import sys

# DLL nào của package nào. Tên file khớp prefix trong package tương ứng.
PACKAGE_DLLS = {
    "Unity.RenderPipeline.Universal": "com.unity.render-pipelines.universal",
    "Unity.RenderPipelines.Universal": "com.unity.render-pipelines.universal",
    "Unity.RenderPipeline.Core": "com.unity.render-pipelines.core",
    "Unity.RenderPipelines.Core": "com.unity.render-pipelines.core",
    "Unity.RenderPipelines.ShaderGraph": "com.unity.shadergraph",
    "Unity.TextMeshPro": "com.unity.textmeshpro",
    "Unity.2D.": "com.unity.2d.sprite",
    "Unity.Mathematics": "com.unity.mathematics",
    "Unity.Burst": "com.unity.burst",
    "Unity.Collections": "com.unity.collections",
    "Unity.Postprocessing": "com.unity.postprocessing",
    "Unity.InputSystem": "com.unity.inputsystem",
    "Unity.Addressables": "com.unity.addressables",
    "Unity.ResourceManager": "com.unity.resourcemanager",
    "Unity.ScriptableBuildPipeline": "com.unity.scriptablebuildpipeline",
    "Unity.Services.Core": "com.unity.services.core",
    "Unity.Services.Analytics": "com.unity.services.analytics",
    "Unity.Services.Authentication": "com.unity.services.authentication",
    "Unity.MemoryProfiler": "com.unity.memoryprofiler",
    "Unity.Profiling.Core": "com.unity.profiling.core",
    "Unity.AdaptivePerformance": "com.unity.adaptiveperformance",
    "Unity.RenderPipelines.Universal.Config": "com.unity.render-pipelines.universal-config",
    "Unity.RenderPipeline.Universal.ShaderLibrary": "com.unity.render-pipelines.universal",
    "Unity.RenderPipelines.Core.ShaderLibrary": "com.unity.render-pipelines.core",
    "Unity.RenderPipelines.Core.Runtime.Shared": "com.unity.render-pipelines.core",
    "Unity.RenderPipelines.GPUDriven": "com.unity.render-pipelines.core",
    "Unity.InternalAPIEngineBridge": "com.unity.render-pipelines.core",
    "Unity.RenderPipelines.Universal.Shaders": "com.unity.render-pipelines.universal",
    "Unity.RenderPipelines.Universal.2D": "com.unity.render-pipelines.universal",
    "Unity.RenderPipelines.Universal.ShaderLibrary": "com.unity.render-pipelines.universal",
}

# Package này đã có sẵn trong Unity 6000 (BuiltInPackages) → không cần tải.
BUILTIN_VERSIONS = {
    "com.unity.render-pipelines.universal": "17.0.4",
    "com.unity.render-pipelines.core": "17.0.4",
    "com.unity.shadergraph": "17.0.4",
    "com.unity.textmeshpro": "3.0.9",
    "com.unity.2d.sprite": "1.0.0",
    "com.unity.mathematics": "1.3.2",
    "com.unity.burst": "1.8.24",
    "com.unity.collections": "2.5.1",
    "com.unity.postprocessing": "3.2.1",
    "com.unity.inputsystem": "1.14.2",
    "com.unity.addressables": "2.6.2",
    "com.unity.resourcemanager": "1.1.0",
    "com.unity.scriptablebuildpipeline": "2.1.3",
    "com.unity.services.core": "1.12.5",
    "com.unity.services.analytics": "5.1.0",
    "com.unity.services.authentication": "3.3.1",
    "com.unity.memoryprofiler": "1.1.6",
    "com.unity.profiling.core": "1.0.2",
    "com.unity.adaptiveperformance": "5.0.0",
    "com.unity.render-pipelines.universal-config": "17.0.3",
}

PROJECT = sys.argv[1]
APPLY = "--apply" in sys.argv
PLUGINS = os.path.join(PROJECT, "Assets", "Plugins")
MANIFEST = os.path.join(PROJECT, "Packages", "manifest.json")

if not os.path.isdir(PLUGINS):
    print(f"❌ Không thấy {PLUGINS}")
    sys.exit(1)

# --- Tìm DLL cần thay ---
to_remove = {}   # package -> [files]
for f in sorted(os.listdir(PLUGINS)):
    if not f.lower().endswith(".dll"):
        continue
    base = f[:-4]
    for prefix, pkg in PACKAGE_DLLS.items():
        if base.startswith(prefix):
            to_remove.setdefault(pkg, []).append(f)
            break

print(f"Tìm thấy {sum(len(v) for v in to_remove.values())} DLL thuộc {len(to_remove)} package:\n")
for pkg, files in sorted(to_remove.items()):
    print(f"  {pkg}")
    for f in files:
        print(f"      - {f}")

# --- Thêm package vào manifest ---
if os.path.isfile(MANIFEST):
    with open(MANIFEST) as fh:
        manifest = json.load(fh)
else:
    manifest = {"dependencies": {}}
deps = manifest.setdefault("dependencies", {})

print("\n→ Cập nhật manifest.json:")
for pkg in sorted(to_remove):
    if pkg in deps:
        print(f"  = {pkg} (đã có: {deps[pkg]})")
        continue
    ver = BUILTIN_VERSIONS.get(pkg)
    if ver:
        deps[pkg] = ver
        print(f"  + {pkg} = {ver}")
    else:
        print(f"  ? {pkg} — chưa biết version, cần tra registry")

if not APPLY:
    print("\n(Chạy lại với --apply để thực thi)")
    sys.exit(0)

# --- Ghi manifest ---
with open(MANIFEST, "w") as fh:
    json.dump(manifest, fh, indent=2)

# --- Xoá DLL + .meta ---
removed = 0
for pkg, files in to_remove.items():
    for f in files:
        for target in (os.path.join(PLUGINS, f), os.path.join(PLUGINS, f + ".meta")):
            if os.path.isfile(target):
                os.remove(target)
                removed += 1

print(f"\n✅ Đã xoá {removed} file (DLL + .meta) và cập nhật manifest.json")
