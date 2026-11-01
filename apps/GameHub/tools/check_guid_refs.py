#!/usr/bin/env python3
"""Kiểm tra các tham chiếu GUID trong project Unity export từ AssetRipper."""
import os
import re
import sys
import collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ASSETS = os.path.join(ROOT, "Assets")

guid_re = re.compile(rb"guid:\s*([0-9a-f]{32})")

# Thu thập guid có trong project
known = set()
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith(".meta"):
            continue
        try:
            with open(os.path.join(dirpath, f), "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        m = re.search(rb"^guid:\s*([0-9a-f]{32})", data, re.M)
        if m:
            known.add(m.group(1).decode())

print(f"Guid trong project: {len(known)}")

# Thu thập mọi tham chiếu GUID trong file asset (không phải .meta)
missing = collections.Counter()
total = 0
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if f.endswith(".meta"):
            continue
        path = os.path.join(dirpath, f)
        try:
            if os.path.getsize(path) > 40 * 1024 * 1024:
                continue
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        for m in guid_re.finditer(data):
            g = m.group(1).decode()
            total += 1
            if g not in known:
                missing[(os.path.relpath(path, ASSETS), g)] += 1

print(f"Tổng tham chiếu GUID: {total}")
print(f"Tham chiếu KHÔNG tồn tại: {len(missing)}")
by_guid = collections.Counter()
for (path, g), n in missing.items():
    by_guid[(g, path)] += n
for (g, path), n in by_guid.most_common(40):
    print(f"  MISS {g}  x{n:<3} {path}")
