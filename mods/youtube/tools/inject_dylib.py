#!/usr/bin/env python3
"""Thêm LC_LOAD_DYLIB vào Mach-O mà KHÔNG đụng __LINKEDIT / code.

LIEF khi thêm load command sẽ dựng lại LINKEDIT (symtab, chained fixups, export
trie, chữ ký) — với app lớn như YouTube việc này làm đổi 4 MB LINKEDIT và có
thể hỏng bind/rebase. Script này chỉ ghi vào phần padding của header (giữa
sizeofcmds và section đầu tiên), chèn LC ngay TRƯỚC LC_CODE_SIGNATURE để chữ
ký vẫn là load command cuối, rồi để ldid ký lại.

    inject_dylib.py <macho> <@executable_path/Frameworks/lib.dylib>
"""
import struct
import sys

LC_LOAD_DYLIB = 0xC
LC_CODE_SIGNATURE = 0x1D


def cstr(raw, off):
    end = raw.find(b"\0", off)
    return raw[off:end].decode("utf-8", "replace")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    path, dylib = sys.argv[1], sys.argv[2]
    name = dylib.encode() + b"\0"
    cmdsize = (24 + len(name) + 7) & ~7

    raw = bytearray(open(path, "rb").read())
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, res = struct.unpack_from("<IiiIIIII", raw, 0)
    if magic != 0xFEEDFACF:
        raise SystemExit(f"không phải Mach-O 64: magic=0x{magic:x}")
    header_end = 32 + sizeofcmds

    # Đã có LC_LOAD_DYLIB này? (so sánh tên)
    off = 32
    sig_off = None
    for i in range(ncmds):
        cmd, size = struct.unpack_from("<II", raw, off)
        if cmd == LC_LOAD_DYLIB:
            n = cstr(raw, off + struct.unpack_from("<I", raw, off + 8)[0])
            if n == dylib:
                print(f"→ {dylib} đã có trong load commands, bỏ qua")
                return
        if cmd == LC_CODE_SIGNATURE:
            sig_off = off
        off += size

    # Vị trí chèn: ngay trước LC_CODE_SIGNATURE nếu nó là LC cuối, ngược lại cuối bảng.
    if sig_off is not None and sig_off + struct.unpack_from("<I", raw, sig_off)[0] == header_end:
        insert_at = sig_off
    else:
        insert_at = header_end

    # Cần đủ chỗ đệm tới section/file dữ liệu đầu tiên (__TEXT.__text = 0x4000
    # với binary của Apple; kiểm tra bằng section header thật).
    text_off = first_section_offset(raw, ncmds)
    if header_end + cmdsize > text_off:
        raise SystemExit(
            f"không đủ padding trong header: header_end=0x{header_end:x} "
            f"+{cmdsize} > section đầu 0x{text_off:x}")

    # Dịch phần load command phía sau điểm chèn lên cmdsize byte.
    tail = bytes(raw[insert_at:header_end])
    raw[insert_at:insert_at + cmdsize] = b"\0" * cmdsize
    raw[insert_at + cmdsize:insert_at + cmdsize + len(tail)] = tail

    # Ghi LC mới.
    cmd = struct.pack("<IIIIII", LC_LOAD_DYLIB, cmdsize, 24, 2, 0, 0)
    raw[insert_at:insert_at + 24] = cmd
    raw[insert_at + 24:insert_at + 24 + len(name)] = name

    struct.pack_into("<II", raw, 16, ncmds + 1, sizeofcmds + cmdsize)
    open(path, "wb").write(raw)
    print(f"→ chèn LC_LOAD_DYLIB {dylib} ({cmdsize} byte, trước LC cuối) — "
          f"padding còn {text_off - header_end - cmdsize}")


def first_section_offset(raw, ncmds):
    off = 32
    best = None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", raw, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from("<I", raw, off + 64)[0]
            so = off + 72
            for _ in range(nsects):
                _, _, o = struct.unpack_from("<QQI", raw, so + 32)
                if o and (best is None or o < best):
                    best = o
                so += 80
        off += size
    return best if best is not None else 0


if __name__ == "__main__":
    main()
