#!/usr/bin/env python3
"""
Giải nén file `.rpa` của Ren'Py thành file rời.

Vì sao cần?
    Bản web của Ren'Py gói **toàn bộ** dữ liệu game vào một file `game.zip`.
    Nếu game có archive `.rpa` lớn (vài GB) thì `game.zip` cũng vài GB →
    trình duyệt phải nạp hết vào RAM → iOS/WebKit báo
    `RangeError: Array buffer allocation failed`.

    Ren'Py web hỗ trợ **progressive download**: file được đánh dấu `+` trong
    `progressive_download.txt` sẽ nằm riêng, tải theo nhu cầu thay vì nằm
    trong `game.zip`. Nhưng rules chỉ khớp theo *đường dẫn*, nên file `.rpa`
    (một archive gộp) không thể tách.

    → Giải nén `.rpa` ra thành file rời trong `game/` → rules áp dụng được →
    `game.zip` chỉ còn vài MB, phần còn lại tải theo nhu cầu.

Hỗ trợ định dạng RPA-1.0/2.0/3.0.

Cách dùng:
    python3 tools/renpy_unpack_rpa.py <thư-mục-game> [--dry-run]
"""
import os
import pickle
import shutil
import sys
import zlib

APPLY = "--dry-run" not in sys.argv


def read_index(path):
    """→ dict {tên_file: [(offset, length, prefix?), ...]}"""
    with open(path, "rb") as f:
        header = f.read(40)
        if header.startswith(b"RPA-3.0 "):
            offset = int(header[8:24], 16)
            key = int(header[25:33], 16)
            f.seek(offset)
            index = pickle.loads(zlib.decompress(f.read()))
            out = {}
            for k, v in index.items():
                if len(v[0]) == 2:
                    out[k] = [(o ^ key, d ^ key) for o, d in v]
                else:
                    out[k] = [(o ^ key, d ^ key, s) for o, d, s in v]
            return out
        if header.startswith(b"RPA-2.0 "):
            offset = int(header[8:], 16)
            f.seek(offset)
            return pickle.loads(zlib.decompress(f.read()))
        if header.startswith(b"\x78\x9c"):
            f.seek(0)
            return pickle.loads(zlib.decompress(f.read()))
    raise ValueError("Không nhận diện được định dạng RPA")


def extract(rpa_path, out_root, index_filter=None):
    """Giải nén mọi file trong rpa vào out_root. → (số file, tổng byte)"""
    index = read_index(rpa_path)
    count = 0
    total = 0
    with open(rpa_path, "rb") as f:
        for name, entries in index.items():
            # name dạng "path/to/file.ext"
            rel = name.replace("\\", "/")
            if index_filter and not index_filter(rel):
                continue
            dest = os.path.join(out_root, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as out:
                for entry in entries:
                    if len(entry) == 2:
                        offset, length = entry
                        prefix = b""
                    else:
                        offset, length, prefix = entry
                        if isinstance(prefix, str):
                            prefix = prefix.encode("latin-1")
                    f.seek(offset)
                    data = f.read(length)
                    if prefix:
                        # Với entry 3 phần tử, phần đầu là dữ liệu "raw"
                        # nằm trước offset.
                        out.write(prefix)
                    out.write(data)
            count += 1
            total += os.path.getsize(dest)
    return count, total


def main():
    if len(sys.argv) < 2:
        print("Usage: renpy_unpack_rpa.py <thư-mục-game> [--dry-run]")
        return 1
    game = os.path.abspath(sys.argv[1])
    if not os.path.isdir(game):
        print(f"❌ Không thấy {game}")
        return 1

    game_dir = os.path.join(game, "game")
    if not os.path.isdir(game_dir):
        print(f"❌ Không thấy {game_dir}")
        return 1

    rpas = [f for f in sorted(os.listdir(game_dir)) if f.lower().endswith(".rpa")]
    if not rpas:
        print("✅ Không có file .rpa nào cần giải nén.")
        return 0

    for rpa in rpas:
        p = os.path.join(game_dir, rpa)
        try:
            index = read_index(p)
        except Exception as e:
            print(f"❌ {rpa}: {e}")
            continue

        size = os.path.getsize(p)
        print(f"\n→ {rpa}  ({size/1048576:.1f} MB, {len(index)} file)")

        # Bỏ qua archive rỗng
        if not index:
            print("   (rỗng — bỏ qua)")
            continue

        if not APPLY:
            biggest = sorted(index.items(), key=lambda kv: -len(kv[0]))[:3]
            for k, v in biggest:
                print(f"   {k}")
            print("   (dry-run — thêm --apply để giải nén)")
            continue

        dest = os.path.join(game_dir, "_unpacked_" + os.path.splitext(rpa)[0])
        os.makedirs(dest, exist_ok=True)
        n, total = extract(p, dest)
        print(f"   ✅ Giải nén {n} file ({total/1048576:.1f} MB) → {os.path.relpath(dest, game)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
