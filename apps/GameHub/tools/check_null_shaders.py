#!/usr/bin/env python3
"""
Tìm asset nào có m_Shader rỗng / guid không resolve được trong project Unity.

AssetRipper đôi khi export material với `m_Shader: {fileID: 0}` (null) khi
không tìm được shader → runtime Unity log "Cannot create required material
because shader is null".
"""
import os
import re
import sys
import collections

ROOT = sys.argv[1]
ASSETS = os.path.join(ROOT, "Assets")

guid_to_file = {}
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith(".meta"):
            continue
        path = os.path.join(dirpath, f)
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        m = re.search(rb"^guid:\s*([0-9a-f]{32})", data, re.M)
        if m:
            guid_to_file[m.group(1).decode()] = path[:-5]

shader_re = re.compile(rb"m_Shader:\s*\{fileID:\s*(-?\d+)(?:,\s*guid:\s*([0-9a-f]{32}))?")
null_shader = collections.Counter()
unknown = collections.Counter()

for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith((".mat", ".prefab", ".unity", ".asset")):
            continue
        path = os.path.join(dirpath, f)
        rel = os.path.relpath(path, ASSETS)
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        for m in shader_re.finditer(data):
            fid = int(m.group(1))
            g = m.group(2).decode() if m.group(2) else None
            if fid == 0 and g is None:
                null_shader[rel] += 1
            elif g and g not in guid_to_file:
                unknown[(rel, g)] += 1

print(f"Material có m_Shader NULL: {len(null_shader)} file")
for rel, n in null_shader.most_common(20):
    print(f"  {n:>3}x  {rel}")

print(f"\nMaterial trỏ shader guid không tồn tại: {len(unknown)}")
for (rel, g), n in unknown.most_common(20):
    print(f"  {n:>3}x  {rel} -> {g}")
