#!/usr/bin/env python3
"""
Tìm các asset trong project Unity export có m_Script trỏ tới DLL sắp bị xoá
(vì package URP sẽ cung cấp lại các DLL đó).
"""
import os
import re
import sys

ROOT = sys.argv[1]
ASSETS = os.path.join(ROOT, "Assets")
PLUGINS = os.path.join(ASSETS, "Plugins")

# Các DLL do package URP/SRP cung cấp (sẽ bị xoá khỏi Assets/Plugins)
PATTERNS = [
    "Unity.RenderPipelines.Universal",
    "Unity.RenderPipeline.Universal",
    "Unity.RenderPipelines.Core",
    "Unity.RenderPipelines.ShaderGraph",
    "Unity.RenderPipelines.GPUDriven",
    "Unity.Burst",
    "Unity.Collections",
    "Unity.Mathematics",
    "Unity.InternalAPIEngineBridge",
]

dll_guid = {}
for f in sorted(os.listdir(PLUGINS)):
    if not f.endswith(".dll"):
        continue
    if not any(f.startswith(p) for p in PATTERNS):
        continue
    meta = os.path.join(PLUGINS, f + ".meta")
    if not os.path.isfile(meta):
        continue
    with open(meta, "r", errors="ignore") as fh:
        m = re.search(r"^guid:\s*([0-9a-f]{32})", fh.read(), re.M)
    if m:
        dll_guid[m.group(1)] = f

print("DLL sẽ bị xoá (guid → tên):")
for g, f in dll_guid.items():
    print(f"  {g}  {f}")

# Tìm asset tham chiếu các guid đó
print("\nAsset tham chiếu (m_Script) tới các DLL trên:")
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if f.endswith(".meta"):
            continue
        path = os.path.join(dirpath, f)
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        for m in re.finditer(rb"m_Script:\s*\{fileID:\s*(-?\d+),\s*guid:\s*([0-9a-f]{32})", data):
            g = m.group(2).decode()
            if g in dll_guid:
                rel = os.path.relpath(path, ASSETS)
                print(f"  {rel}  fileID={m.group(1).decode()}  -> {dll_guid[g]}")
                break
