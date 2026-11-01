#!/usr/bin/env python3
"""Đọc header của file .asar (Electron/NW.js) — dùng để khảo sát cấu trúc.

Định dạng .asar (Chromium):
  offset 0 : uint32 = 4              (kích thước pickle header đầu tiên)
  offset 4 : uint32 = headerSize     (kích thước pickle chứa JSON header)
  offset 8 : uint32 = headerStrSize  (kích thước chuỗi JSON + padding)
  offset 12: uint32 = headerStrLen   (độ dài JSON thực tế)
  offset 16: JSON header
  offset 8+headerSize: bắt đầu dữ liệu file

JSON header: {"files":{"name":{"size":N,"offset":"O","unpacked":bool}}}
  - file có "files" con => thư mục
  - "unpacked": true => nằm ngoài archive (file riêng cạnh .asar)
  - "offset" là chỉ số byte tương đối so với dataOffset
"""
import json
import os
import struct
import sys


def read_header(path):
    with open(path, "rb") as f:
        raw = f.read(16)
        if len(raw) < 16:
            raise ValueError("file quá nhỏ")
        _, header_size, header_str_size, header_str_len = struct.unpack("<IIII", raw)
        if header_str_len > 100 * 1024 * 1024:
            raise ValueError("header size không hợp lý")
        js = f.read(header_str_len).decode("utf-8")
        return json.loads(js), 8 + header_size, header_str_size


def walk(node, prefix=""):
    for name, meta in node.get("files", {}).items():
        path = f"{prefix}/{name}" if prefix else name
        if "files" in meta:
            yield from walk(meta, path)
        else:
            yield path, meta


def main():
    for path in sys.argv[1:]:
        print(f"\n=== {path}  ({os.path.getsize(path)/1e6:.1f} MB)")
        try:
            header, data_offset, _ = read_header(path)
        except Exception as e:
            print("  LỖI:", e)
            continue
        files = list(walk(header))
        total = sum(m.get("size", 0) for _, m in files)
        unpacked = sum(1 for _, m in files if m.get("unpacked"))
        print(f"  dataOffset={data_offset}  entries={len(files)}  "
              f"tổng size={total/1e6:.1f} MB  unpacked={unpacked}")
        for p, m in files[:15]:
            print(f"    {p[:70]:72} size={m.get('size',0):>10} off={m.get('offset','-'):>10}")
        if len(files) > 15:
            print(f"    ... và {len(files)-15} file nữa")


if __name__ == "__main__":
    main()
