#!/usr/bin/env python3
"""
Kiểm tra mọi tham chiếu shader trong project đã được đưa vào build hay chưa.

Đối với mỗi tham chiếu `{fileID: 4800000, guid: X}` (shader) trong asset:
  - guid có tồn tại trong project không?
  - shader đó có nằm trong danh sách đã compile của build log không?
"""
import os
import re
import sys
import collections

ROOT = sys.argv[1]
LOG = sys.argv[2] if len(sys.argv) > 2 else "/tmp/unity-build.log"
ASSETS = os.path.join(ROOT, "Assets")

compiled = set()
if os.path.isfile(LOG):
    pat = re.compile(r'Serialized binary data for shader (.+?) in ')
    with open(LOG, "r", errors="ignore") as fh:
        for line in fh:
            m = pat.search(line)
            if m:
                compiled.add(m.group(1))

guid_to_path = {}
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith(".meta"):
            continue
        path = os.path.join(dirpath, f)
        try:
            with open(path, "r", errors="ignore") as fh:
                m = re.search(r"^guid:\s*([0-9a-f]{32})", fh.read(), re.M)
        except OSError:
            continue
        if m:
            guid_to_path[m.group(1)] = path[:-5]

shader_name = {}
for p in guid_to_path.values():
    if p.endswith(".shader"):
        try:
            with open(p, "r", errors="ignore") as fh:
                m = re.search(r'Shader\s+"([^"]+)"', fh.read(4000))
        except OSError:
            continue
        if m:
            shader_name[p] = m.group(1)

# mọi tham chiếu shader
refs = collections.defaultdict(set)   # (guid, name) -> set(file)
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if f.endswith(".meta"):
            continue
        path = os.path.join(dirpath, f)
        try:
            with open(path, "r", errors="ignore") as fh:
                data = fh.read()
        except OSError:
            continue
        for m in re.finditer(r"\{fileID:\s*4800000,\s*guid:\s*([0-9a-f]{32})", data):
            g = m.group(1)
            target = guid_to_path.get(g)
            name = shader_name.get(target, "?" if target else "KHÔNG TỒN TẠI")
            refs[(g, name)].add(os.path.relpath(path, ASSETS))

print(f"Shader đã compile trong build: {len(compiled)}\n")
bad = []
for (g, name), files in sorted(refs.items(), key=lambda x: x[0][1]):
    in_build = name in compiled if name != "?" else False
    status = "OK  " if in_build else "MISS"
    if not in_build:
        bad.append((g, name, files))
    print(f"  {status}  {name:<52} ({len(files)} file)")

if bad:
    print(f"\n=== {len(bad)} shader CHƯA có trong build ===")
    for g, name, files in bad:
        print(f"\n  {name}  (guid {g})")
        for fp in sorted(files)[:5]:
            print(f"      - {fp}")
