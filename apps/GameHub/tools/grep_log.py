#!/usr/bin/env python3
"""Tìm các dòng log quan tâm, bỏ qua các dòng siêu dài (command line)."""
import re
import sys

log = sys.argv[1]
pats = sys.argv[2:]

rx = re.compile("|".join(pats), re.I)
seen = {}
with open(log, "r", errors="ignore") as fh:
    for i, line in enumerate(fh, 1):
        if len(line) > 400:
            continue
        if rx.search(line):
            key = line.strip()[:200]
            seen[key] = seen.get(key, 0) + 1

for k, n in sorted(seen.items(), key=lambda x: -x[1])[:60]:
    print(f"{n:>4}x  {k}")
