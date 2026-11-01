#!/usr/bin/env python3
"""Liệt kê các shader được material tham chiếu + tìm các tham chiếu hỏng."""
import os
import re
import sys
import collections

ROOT = sys.argv[1]
ASSETS = os.path.join(ROOT, "Assets")

guid_re = re.compile(rb"guid:\s*([0-9a-f]{32})")
guid_of_file = {}


def walk_assets():
    for dirpath, _, files in os.walk(ASSETS):
        for f in files:
            yield os.path.join(dirpath, f)


# guid -> đường dẫn file asset (đọc từ .meta)
for path in walk_assets():
    if not path.endswith(".meta"):
        continue
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        continue
    m = re.search(rb"^guid:\s*([0-9a-f]{32})", data, re.M)
    if m:
        target = path[:-5]  # bỏ ".meta"
        guid_of_file[m.group(1).decode()] = target

# tên shader của file .shader
shader_name = {}
for path in walk_assets():
    if not path.endswith(".shader"):
        continue
    try:
        with open(path, "r", errors="ignore") as fh:
            head = fh.read(2000)
    except OSError:
        continue
    m = re.search(r'Shader\s+"([^"]+)"', head)
    if m:
        shader_name[path] = m.group(1)

# tham chiếu shader từ material
usage = collections.Counter()
broken = collections.Counter()
for path in walk_assets():
    if not path.endswith(".mat"):
        continue
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        continue
    m = re.search(rb"m_Shader:\s*\{fileID:\s*(-?\d+),\s*guid:\s*([0-9a-f]{32})", data)
    if not m:
        continue
    g = m.group(2).decode()
    target = guid_of_file.get(g)
    if target is None:
        broken[(os.path.relpath(path, ASSETS), g, "KHÔNG có asset nào mang guid này")] += 1
    elif target.endswith(".shader"):
        usage[shader_name.get(target, os.path.basename(target))] += 1
    else:
        usage["(builtin/other) " + os.path.basename(target)] += 1

print("Shader được material dùng:")
for name, n in usage.most_common():
    print(f"  {n:>3}  {name}")

print("\nTham chiếu hỏng:")
for (p, g, why), n in broken.most_common():
    print(f"  {n:>3}  {p} -> {g}  ({why})")
