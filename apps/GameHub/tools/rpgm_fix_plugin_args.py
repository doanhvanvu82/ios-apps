#!/usr/bin/env python3
"""Tìm/sửa tham số lệnh plugin RPG Maker MZ bị bản dịch máy làm hỏng JSON.

Plugin VisuMZ (và plugin theo quy ước "Tên:kiểu") JSON.parse mọi tham số kiểu
json/struct/func/array… Công cụ dịch (AiNiee…) hay thêm/bớt dấu "\\" trong
chuỗi đã mã hoá JSON, vd `"\\\\\\C[14]…"` → `\\C` không phải escape hợp lệ
→ game crash "JSON.parse" khi chạy tới lệnh đó.

Sửa: chuỗi dấu "\\" lẻ đứng trước ký tự không phải escape JSON hợp lệ —
3+ dấu thì bớt 1 (dịch máy thêm thừa), 1 dấu thì nhân đôi.

Ngoài ra khôi phục giá trị lựa chọn bị dịch sang tiếng Việt (ENUMS): plugin so
sánh đúng chữ tiếng Anh ("Unchanged", "left", "instant"…) hoặc eval() nó →
crash/sai bố cục. Chỉ thay đúng chuỗi trong file (không ghi lại cả file JSON),
có backup *.bak-pluginargs.

Cách dùng:
  python3 rpgm_fix_plugin_args.py <thư_mục_game>          # chỉ liệt kê
  python3 rpgm_fix_plugin_args.py <thư_mục_game> --apply  # sửa thật
"""
import glob
import json
import os
import re
import shutil
import sys

PARSED = {"json", "struct", "func", "arraynum", "arrayeval", "arrayjson", "arraystr", "arraystruct", "arrayfunc"}
BAD_ESCAPE = re.compile(r'(\\+)([^"\\/bfnrtu])')

# Khoá tham số (regex, bỏ phần ":kiểu") → {bản dịch: giá trị gốc}.
ENUMS = [
    (r"alignX", {"trái": "left", "giữa": "center", "phải": "right"}),
    (r"alignY", {"trên": "top", "giữa": "middle", "dưới": "bottom"}),
    (r"appearType", {"mở": "open", "tức thì": "instant"}),
    (r"closeType", {"đóng": "close", "tức thì": "instant"}),
    (r"ScreenSide", {"trái": "left", "phải": "right"}),
    (r"WordWrap", {"Không thay đổi": "No Change", "Bật": "true", "Tắt": "false"}),
    (r"easingType", {"Tuyến tính": "Linear"}),
    (r"Target\w*", {"Không thay đổi": "Unchanged"}),
    (r"Trigger", {"Vào": "Enter", "Ra": "Leave", "Nhấn": "Press", "Nhấp": "Click"}),  # Cae_PictureTouch
]


def restore_enums(text):
    """→ (text mới, [(khoá, bản dịch, gốc, số chỗ)]). Khớp mọi tầng lồng JSON:
    dấu ngoặc của khoá và giá trị có cùng số dấu "\\" đứng trước."""
    changes = []
    for key, table in ENUMS:
        for vi, en in table.items():
            pattern = re.compile(r'(\\*)"(' + key + r'(?::\w+)?)\1":\1"' + re.escape(vi) + r'\1"')
            text, n = pattern.subn(lambda m: f'{m.group(1)}"{m.group(2)}{m.group(1)}":{m.group(1)}"{en}{m.group(1)}"', text)
            if n:
                changes.append((key, vi, en, n))
    return text, changes


def repair(s):
    def fix(m):
        n = len(m.group(1))
        if n % 2 == 0:
            return m.group(0)
        return "\\" * (n - 1 if n >= 3 else 2) + m.group(2)
    return BAD_ESCAPE.sub(fix, s)


def parses(s):
    try:
        json.loads(s)
        return True
    except ValueError:
        return False


def broken_args(args):
    """→ [(khoá, giá trị hỏng)] — chỉ tầng tham số trực tiếp của lệnh."""
    out = []
    for k, v in (args or {}).items():
        if isinstance(v, str) and v and ":" in k and k.rsplit(":", 1)[1].strip().lower() in PARSED and not parses(v):
            out.append((k, v))
    return out


def main(root, apply):
    data = os.path.join(root, "data")
    if not os.path.isdir(data):
        data = os.path.join(root, "www", "data")
    total = fixed = 0
    for path in sorted(glob.glob(os.path.join(data, "*.json"))):
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except ValueError as e:
            print(f"⚠️  {os.path.basename(path)}: file JSON hỏng ({e}) — bỏ qua")
            continue
        found = []

        def walk(o):
            if isinstance(o, dict):
                p = o.get("parameters")
                if o.get("code") == 357 and isinstance(p, list) and len(p) > 3 and isinstance(p[3], dict):
                    found.extend((p[0], p[1], k, v) for k, v in broken_args(p[3]))
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(doc)
        original = text = open(path, encoding="utf-8").read()
        text, changes = restore_enums(text)
        for key, vi, en, n in changes:
            total += n
            fixed += n
            print(f"✅ {os.path.basename(path)} {key}: {vi!r} → {en!r} ({n} chỗ)")
        for plugin, command, key, value in found:
            total += 1
            new = repair(value)
            ok = parses(new)
            print(f"{'✅' if ok else '❌'} {os.path.basename(path)} {plugin}/{command} {key}: {value[:70]!r}"
                  + ("" if ok else "  (không tự sửa được)"))
            if not ok:
                continue
            old_raw = json.dumps(value, ensure_ascii=False)[1:-1]
            new_raw = json.dumps(new, ensure_ascii=False)[1:-1]
            # Thay mọi chỗ: lệnh trùng nhau và dòng hiển thị (code 657) có cùng chuỗi.
            text = text.replace(old_raw, new_raw)
            if new_raw in text:
                fixed += 1
        if apply and text != original:
            json.loads(text)
            backup = path + ".bak-pluginargs"
            if not os.path.exists(backup):
                shutil.copy2(path, backup)
            tmp = path + ".tmp"
            open(tmp, "w", encoding="utf-8").write(text)
            os.replace(tmp, path)
    if not total:
        print("✅ Không có tham số plugin nào hỏng JSON hay bị dịch nhầm.")
    elif not apply:
        print(f"→ {total} tham số hỏng. Chạy lại với --apply để sửa.")
    else:
        print(f"→ Đã sửa {fixed}/{total}.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], "--apply" in sys.argv[2:])
