#!/usr/bin/env python3
"""Liệt kê file trong .pck của Godot 3 (pack version 1 và 2).

Godot 3 pack v1: header cố định 84 byte, directory nằm ở CUỐI file.
Godot 3 pack v2: có pack_flags/file_base/dir_offset trong header.
"""
import os
import struct
import sys


def _read_dir_v1(data):
    """Dò directory ở cuối file (pack v1)."""
    # Thử các offset gần cuối: tìm uint32 hợp lệ làm file_count.
    tail_start = max(0, len(data) - 4 * 1024 * 1024)
    for q in range(len(data) - 4, tail_start, -4):
        count = struct.unpack_from("<I", data, q)[0]
        if count == 0 or count > 200000:
            continue
        try:
            entries = _parse_dir_v1(data, q + 4, count)
        except Exception:
            continue
        if entries and all(e[0].startswith("res://") for e in entries):
            return entries
    return []


def _parse_dir_v1(data, p, count):
    entries = []
    for _ in range(count):
        if p + 4 > len(data):
            raise ValueError("hết data")
        plen = struct.unpack_from("<I", data, p)[0]
        p += 4
        if plen == 0 or plen > 4096 or p + plen > len(data):
            raise ValueError("path len sai")
        path = data[p:p + plen].rstrip(b"\x00").decode("utf-8", "replace")
        p += plen
        off = struct.unpack_from("<Q", data, p)[0]
        p += 8
        size = struct.unpack_from("<I", data, p)[0]
        p += 4
        p += 16  # md5
        entries.append((path, off, size))
    return entries


def _parse_dir_v2(data, p, count):
    entries = []
    for _ in range(count):
        plen = struct.unpack_from("<I", data, p)[0]
        p += 4
        path = data[p:p + plen].rstrip(b"\x00").decode("utf-8", "replace")
        p += plen
        off = struct.unpack_from("<I", data, p)[0]
        p += 4
        size = struct.unpack_from("<I", data, p)[0]
        p += 4
        p += 16  # md5
        p += 4   # flags
        entries.append((path, off, size))
    return entries


def read_pck(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"GDPC":
        raise SystemExit("Không phải pck Godot")
    pack_ver = struct.unpack_from("<I", data, 4)[0]
    engine = struct.unpack_from("<III", data, 8)
    print(f"pack_ver={pack_ver} engine={engine}")

    if pack_ver >= 2:
        pack_flags = struct.unpack_from("<I", data, 20)[0]
        file_base = struct.unpack_from("<I", data, 24)[0]
        dir_offset = struct.unpack_from("<I", data, 28)[0]
        p = 32 + 16 * 4  # reserved[16]
        count = struct.unpack_from("<I", data, p)[0]
        p += 4
        print(f"dir_offset={dir_offset} count={count}")
        return _parse_dir_v2(data, p, count)

    # pack v1 — directory ở cuối file
    entries = _read_dir_v1(data)
    return entries


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: pck_ls.py <file.pck> [filter]")
    pck = sys.argv[1]
    if not os.path.isfile(pck):
        raise SystemExit(f"Không thấy file: {pck}")
    entries = read_pck(pck)
    print(f"=== {len(entries)} file ===")
    pat = sys.argv[2].lower() if len(sys.argv) > 2 else None
    hits = [(size, path) for path, off, size in entries
            if pat is None or pat in path.lower()]
    for size, path in sorted(hits, reverse=True):
        print(f"{size:>12}  {path}")
