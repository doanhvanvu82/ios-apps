#!/usr/bin/env python3
"""
Sửa lỗi compile `CS0457: Ambiguous user defined conversions` cho game Naninovel.

Nguyên nhân:
    `Naninovel.DecimalParameter` (và `IntegerParameter`, `BooleanParameter`) định
    nghĩa **hai** operator chuyển đổi ngầm định:

        implicit operator float?(DecimalParameter)     ← do Naninovel định nghĩa
        implicit operator float(DecimalParameter)      ← do C# sinh từ struct field

    Khi code decompile viết `(float)Interval`, trình biên dịch không biết chọn
    operator nào → CS0457 "Ambiguous user defined conversions".

Cách sửa:
    Ép kiểu qua property `Value` (kiểu gốc `float`) rồi mới ép kiểu:

        (float)Interval          →  (float)Interval.Value
        (int)Count               →  (int)Count.Value
        new Tween(Fade)          →  new Tween(Fade.Value)

Cấu trúc class Naninovel:
    DecimalParameter : CommandParameter<float> : Nullable<float>
    → `Nullable<T>` có property `Value` (kiểu `T`, không phải `T?`)

Cách dùng:
    python3 tools/unity_fix_naninovel_params.py <project-dir> [--apply]
"""
import os
import re
import sys

APPLY = "--apply" in sys.argv

PARAM_TYPES = ("DecimalParameter", "IntegerParameter", "BooleanParameter", "StringParameter")

# `(float)X` / `(int)X` / `(bool)X` — X là field kiểu parameter
CAST_RE = re.compile(
    r"\((float|int|bool|double)\)\s*([A-Za-z_][A-Za-z0-9_]*)\b(?!\s*\.)"
)

# `new Tween(X)` — X là field kiểu parameter
NEWTWEEN_RE = re.compile(r"new Tween\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)")


def is_param_field(text, name):
    """Field có kiểu Naninovel parameter không?

    Nhận diện cả 2 dạng khai báo:
        public DecimalParameter Interval = 0.01f;     (field)
        public DecimalParameter Interval { get; set; } (property)
    """
    esc = re.escape(name)
    field_pat = re.compile(
        rf"\b(?:public|private|protected|internal)\s+(?:static\s+)?(?:readonly\s+)?"
        rf"({'|'.join(PARAM_TYPES)})\s+{esc}\b"
    )
    if field_pat.search(text):
        return True
    prop_pat = re.compile(
        rf"\b(?:public|private|protected|internal)\s+(?:static\s+)?"
        rf"({'|'.join(PARAM_TYPES)})\s+{esc}\s*\{{"
    )
    return bool(prop_pat.search(text))


def fix_text(text):
    """→ (text_mới, số_chỗ_sửa)"""
    new = text
    spots = 0

    # 1) Chuẩn hoá: gỡ hậu tố `.Value`/`.value` đã gắn trước đó (idempotent)
    for pat in (r"([A-Za-z_][A-Za-z0-9_]*)\.Value\.value\b",
                r"([A-Za-z_][A-Za-z0-9_]*)\.value\.Value\b"):
        for m in list(re.finditer(pat, new)):
            if is_param_field(new, m.group(1)):
                new = new.replace(m.group(0), f"{m.group(1)}.Value")
                spots += 1

    # 2) `(float)X` → `(float)X.Value`  (chỉ khi X là field parameter và chưa có .Value)
    for m in list(CAST_RE.finditer(new)):
        typ, name = m.group(1), m.group(2)
        tail = new[m.end():m.end() + 7]
        if tail.lstrip().startswith("."):
            continue
        if not is_param_field(new, name):
            continue
        new = new.replace(m.group(0), f"({typ}){name}.Value")
        spots += 1

    # 3) `new Tween(X)` → `new Tween(X.Value)`
    for m in list(NEWTWEEN_RE.finditer(new)):
        name = m.group(1)
        if not is_param_field(new, name):
            continue
        new = new.replace(m.group(0), f"new Tween({name}.Value)")
        spots += 1

    return new, spots


def main():
    if len(sys.argv) < 2:
        print("Usage: unity_fix_naninovel_params.py <project-dir> [--apply]")
        return 1
    project = os.path.abspath(sys.argv[1])
    if not os.path.isdir(project):
        print(f"❌ Không thấy {project}")
        return 1

    changed_files = 0
    changed_spots = 0

    for dp, dn, fn in os.walk(project):
        if "Library" in dp or "Temp" in dp or "obj" in dp:
            dn[:] = []
            continue
        for f in fn:
            if not f.endswith(".cs"):
                continue
            p = os.path.join(dp, f)
            try:
                with open(p, encoding="utf-8", errors="ignore") as fh:
                    text = fh.read()
            except OSError:
                continue
            if not any(t in text for t in PARAM_TYPES):
                continue

            new, spots = fix_text(text)
            if new != text:
                changed_files += 1
                changed_spots += spots
                print(f"  ✏️  {os.path.relpath(p, project)}  ({spots} chỗ)")
                if APPLY:
                    with open(p, "w", encoding="utf-8") as fh:
                        fh.write(new)

    print()
    if changed_files == 0:
        print("✅ Không tìm thấy chỗ ép kiểu gây mơ hồ.")
        return 0
    print(f"Tìm thấy {changed_spots} chỗ trong {changed_files} file.")
    if APPLY:
        print(f"✅ Đã sửa {changed_files} file")
    else:
        print("(Chạy lại với --apply để sửa)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
