#!/usr/bin/env python3
"""So sánh shader có trong project với shader đã được compile trong build log."""
import re
import sys

log = sys.argv[1]
root = sys.argv[2]

compiled = set()
pat = re.compile(r'Compiling shader "([^"]+)"')
with open(log, "r", errors="ignore") as fh:
    for line in fh:
        m = pat.search(line)
        if m:
            compiled.add(m.group(1))

print(f"Shader đã compile trong build: {len(compiled)}")

# Shader có trong project (tên lấy từ nội dung file .shader)
import os
project = set()
for dirpath, _, files in os.walk(os.path.join(root, "Assets")):
    for f in files:
        if not f.endswith(".shader"):
            continue
        path = os.path.join(dirpath, f)
        try:
            with open(path, "r", errors="ignore") as fh:
                head = fh.read(2000)
        except OSError:
            continue
        m = re.search(r'Shader\s+"([^"]+)"', head)
        if m:
            project.add(m.group(1))

print(f"Shader trong project: {len(project)}")
missing = sorted(project - compiled)
print(f"\nShader trong project KHÔNG được compile ({len(missing)}):")
for s in missing:
    print("  -", s)
