#!/usr/bin/env python3
"""Xử lý tên file/thư mục chỉ khác nhau chữ hoa/thường trong Assets/.

Game làm trên Windows/macOS (không phân biệt hoa/thường) hay có `Resources` + `resources`,
`Scenes` + `scenes`… Trên Linux Unity báo "Case sensitive file systems are not fully
supported" và BỎ QUA một trong hai (thư mục Scenes/Resources của game có thể biến mất),
build sau đó có thể crash. Làm giống Windows:
  - thư mục trùng tên → gộp nội dung vào một thư mục (giữ tên viết hoa/đứng trước);
  - file trùng tên → giữ một, file kia đổi thành <tên>_dup<N><đuôi> (cùng .meta, GUID giữ nguyên
    nên tham chiếu theo GUID vẫn đúng).

Dùng: unity_case_collisions.py <ExportedProject>
"""
import collections
import os
import shutil
import sys


def unique(directory, name):
    stem, ext = os.path.splitext(name)
    n = 1
    while os.path.exists(os.path.join(directory, f"{stem}_dup{n}{ext}")):
        n += 1
    return f"{stem}_dup{n}{ext}"


def move_entry(src, dst_dir, name):
    """Chuyển src vào dst_dir/name (cùng .meta). Trùng đúng tên → thư mục thì gộp, file thì đổi tên."""
    dst = os.path.join(dst_dir, name)
    if os.path.isdir(src) and os.path.isdir(dst):
        merge_dirs(src, dst)
        return
    if os.path.exists(dst):
        name = unique(dst_dir, name)
        dst = os.path.join(dst_dir, name)
    shutil.move(src, dst)
    if os.path.exists(src + ".meta"):
        shutil.move(src + ".meta", dst + ".meta")


def merge_dirs(src, dst):
    listing = sorted(os.listdir(src))
    names = set(listing)
    for child in listing:
        if child.endswith(".meta") and child[:-5] in names:
            continue  # .meta đi cùng file/thư mục của nó (move_entry chuyển cả hai)
        move_entry(os.path.join(src, child), dst, child)
    shutil.rmtree(src, ignore_errors=True)
    if os.path.exists(src + ".meta"):
        os.remove(src + ".meta")


def fix_directory(path):
    fixed = 0
    while True:
        groups = collections.defaultdict(list)
        for entry in sorted(os.listdir(path)):
            if not entry.endswith(".meta") or not os.path.exists(os.path.join(path, entry[:-5])):
                groups[entry.lower()].append(entry)
        duplicate = next((g for g in groups.values() if len(g) > 1), None)
        if duplicate is None:
            break
        keep = duplicate[0]
        for other in duplicate[1:]:
            move_entry(os.path.join(path, other), path, keep if os.path.isdir(os.path.join(path, other)) else unique(path, other))
            fixed += 1
    for entry in sorted(os.listdir(path)):
        sub = os.path.join(path, entry)
        if os.path.isdir(sub):
            fixed += fix_directory(sub)
    return fixed


def main():
    assets = os.path.join(os.path.abspath(sys.argv[1]), "Assets")
    fixed = fix_directory(assets)
    if fixed:
        print(f"✅ Tên trùng hoa/thường: xử lý {fixed} chỗ (gộp thư mục, đổi tên file trùng)")


if __name__ == "__main__":
    main()
