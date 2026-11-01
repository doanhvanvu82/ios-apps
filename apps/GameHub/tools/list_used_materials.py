#!/usr/bin/env python3
"""Liệt kê mọi material mà scene/prefab tham chiếu, kèm shader của nó."""
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

shader_name = {}
for path in guid_to_file.values():
    if path.endswith(".shader"):
        try:
            with open(path, "r", errors="ignore") as fh:
                head = fh.read(2000)
        except OSError:
            continue
        m = re.search(r'Shader\s+"([^"]+)"', head)
        if m:
            shader_name[path] = m.group(1)

# material guid -> tên file
mat_name = {}
for g, p in guid_to_file.items():
    if p.endswith(".mat"):
        mat_name[g] = os.path.basename(p)

# Tìm mọi tham chiếu {fileID: 2100000, guid: X} (material) trong scene/prefab
used = collections.Counter()
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith((".unity", ".prefab")):
            continue
        path = os.path.join(dirpath, f)
        rel = os.path.relpath(path, ASSETS)
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        for m in re.finditer(rb"\{fileID:\s*2100000,\s*guid:\s*([0-9a-f]{32})", data):
            g = m.group(1).decode()
            target = guid_to_file.get(g)
            if target is None:
                used[("MISSING", g, rel)] += 1
            elif target.endswith(".mat"):
                # đọc shader của material đó
                try:
                    with open(target, "rb") as fh:
                        mdata = fh.read()
                except OSError:
                    continue
                sm = re.search(rb"m_Shader:\s*\{fileID:\s*(-?\d+)(?:,\s*guid:\s*([0-9a-f]{32}))?", mdata)
                sname = "?"
                if sm:
                    if sm.group(1) == b"0" and not sm.group(2):
                        sname = "NULL !!!"
                    elif sm.group(2):
                        st = guid_to_file.get(sm.group(2).decode())
                        sname = shader_name.get(st, os.path.basename(st) if st else "?")
                used[(os.path.basename(target), sname, rel)] += 1

by_shader = collections.Counter()
for (mat, sh, rel), n in used.items():
    by_shader[(sh, mat)] += n

print("Material dùng trong scene/prefab (theo shader):")
for (sh, mat), n in by_shader.most_common(40):
    flag = "  <<< NULL" if sh == "NULL !!!" else ""
    print(f"  {n:>4}x  shader={sh:<45} mat={mat}{flag}")
