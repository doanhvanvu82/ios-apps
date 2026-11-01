#!/usr/bin/env python3
"""Sửa lỗi biên dịch thường gặp của mã AssetRipper dịch ngược, dựa trên log build.

    unity_fix_compile_errors.py <project-dir> <unity-log>
    → exit 0 nếu đã sửa gì đó (nên build lại), 1 nếu không sửa được gì.

- CS0104 tên mơ hồ ('Animation' giữa Spine.Animation và UnityEngine.Animation…)
  → ghi tên đầy đủ tại đúng dòng/cột báo lỗi. Ưu tiên: thư viện game (Spine…)
  hơn UnityEngine, UnityEngine hơn System.
- CS1061 "'float' does not contain a definition for 'Value'" (`x.Value.Value` do
  dịch ngược Nullable của Naninovel) → bỏ `.Value` thừa tại cột báo lỗi.
- CS0592 attribute mồ côi do lần sửa CS1673 cũ để lại → xoá.
- CS0165 biến chưa gán ("int num; _ = num - 2;" do dịch ngược state machine)
  → khai báo `= default`.
- CS1673 lambda trong state machine `struct … : IAsyncStateMachine` mà AssetRipper
  không dựng lại thành `async` → xoá struct nếu chỉ còn được nhắc trong
  [AsyncStateMachine(typeof(…))] (mã chết), nếu không thì đổi struct → class.
- CS0103/CS0246 thiếu kiểu (vd Beautify nằm trong DLL URP cũ đã bị bỏ) → tạm bỏ
  tệp ra khỏi project (PatchBackup/) nếu là script demo/ví dụ, hoặc tệp lá không
  script nào khác tham chiếu tới class của nó. Tệp có nơi khác dùng thì giữ.
- CS0656 AsyncUniTask…AwaitOnCompleted (UniTask.dll bị cắt), CS0121 GetAwaiter
  trùng với Unity 6 → unity_unitask_full.py.
"""
import os
import re
import shutil
import subprocess
import sys

ERROR = re.compile(r"(Assets/[^(\n]+)\((\d+),(\d+)\): error (CS\d+): (.*)")


# Thông báo CS0104 ghi System.Object/String… bằng từ khoá C# (`object`, `string`…).
CSHARP_ALIASES = {"object", "string", "bool", "byte", "sbyte", "short", "ushort", "int", "uint",
                  "long", "ulong", "float", "double", "decimal", "char"}


def preferred(candidates):
    def rank(name):
        if name.startswith("System.") or name in CSHARP_ALIASES:
            return 2
        if name.startswith("UnityEngine."):
            return 1
        return 0
    return sorted(candidates, key=rank)[0]


def fix_ambiguous(lines, line_no, col, message):
    m = re.match(r"'([\w.]+)' is an ambiguous reference between '([\w.]+)' and '([\w.]+)'", message)
    if not m:
        return False
    name, a, b = m.groups()
    idx = line_no - 1
    text = lines[idx]
    start = col - 1
    if text[start:start + len(name)] != name:
        return False
    lines[idx] = text[:start] + preferred([a, b]) + text[start + len(name):]
    return True


def fix_extra_value(lines, line_no, col, message):
    if not re.match(r"'(float|int|bool|string|double)' does not contain a definition for 'Value'", message):
        return False
    idx, start = line_no - 1, col - 1
    text = lines[idx]
    if start < 1 or text[start - 1] != "." or not re.match(r"Value\b", text[start:]):
        return False
    lines[idx] = text[:start - 1] + text[start + len("Value"):]
    return True


def fix_orphan_attribute(lines, line_no):
    """Attribute mồ côi (struct bên dưới đã bị xoá) → xoá cả cụm attribute."""
    idx = line_no - 1
    if not ATTRIBUTE_LINE.match(lines[idx]):
        return False
    end = idx
    while end + 1 < len(lines) and ATTRIBUTE_LINE.match(lines[end + 1]):
        end += 1
    del lines[idx:end + 1]
    return True


def fix_unassigned(lines, line_no, message):
    m = re.match(r"Use of unassigned local variable '(\w+)'", message)
    if not m:
        return False
    var = m.group(1)
    decl = re.compile(r"^(\s*[\w.<>\[\], ]+?\s+" + re.escape(var) + r")\s*;")
    for idx in range(line_no - 1, max(-1, line_no - 400), -1):
        if decl.match(lines[idx]):
            lines[idx] = decl.sub(r"\1 = default;", lines[idx], count=1)
            return True
    return False


ATTRIBUTE_LINE = re.compile(r"^\s*\[[^\]]*\]\s*$")
STATE_MACHINE = re.compile(r"^(\s*)((?:private|internal|public)\s+)?struct\s+(\w+)\s*:\s*IAsyncStateMachine\b")


def fix_state_machines(project, errors):
    """Trả về số state machine đã xử lý."""
    by_file = {}
    for path, line_no, _, code, _ in errors:
        if code == "CS1673":
            by_file.setdefault(path, set()).add(int(line_no))
    done = 0
    for rel, lines_with_error in by_file.items():
        full = os.path.join(project, rel)
        try:
            lines = open(full, encoding="utf-8-sig").read().split("\n")
        except OSError:
            continue
        targets = set()
        for line_no in lines_with_error:
            for idx in range(min(line_no, len(lines)) - 1, -1, -1):
                if STATE_MACHINE.match(lines[idx]):
                    targets.add(idx)
                    break
        for start in sorted(targets, reverse=True):
            name = STATE_MACHINE.match(lines[start]).group(3)
            depth, end, opened = 0, None, False
            for idx in range(start, len(lines)):
                depth += lines[idx].count("{") - lines[idx].count("}")
                opened = opened or "{" in lines[idx]
                if opened and depth <= 0:
                    end = idx
                    break
            if end is None:
                continue
            # Kèm các attribute ngay trên struct ([StructLayout], [CompilerGenerated]).
            while start > 0 and ATTRIBUTE_LINE.match(lines[start - 1]):
                start -= 1
            outside = "\n".join(lines[:start] + lines[end + 1:])
            uses = [m for m in re.finditer(r"\b" + re.escape(name) + r"\b", outside)]
            attr = re.compile(r"^\s*\[AsyncStateMachine\(typeof\(" + re.escape(name) + r"\)\)\]\s*$")
            attr_lines = [i for i, l in enumerate(lines) if attr.match(l)]
            if len(uses) == len(attr_lines):
                del lines[start:end + 1]
                lines = [l for l in lines if not attr.match(l)]
            else:
                lines[start] = lines[start].replace("struct", "class", 1)
            done += 1
        open(full, "w", encoding="utf-8").write("\n".join(lines))
    if done:
        print(f"✅ Sửa {done} state machine async dịch ngược hỏng (CS1673)")
    return done


def removable(project, rel):
    """Script demo/ví dụ, hoặc không script nào khác nhắc tới tên class của nó."""
    if re.search(r"/(Demos?|Examples?|Samples?)/", rel, re.I):
        return True
    name = os.path.splitext(os.path.basename(rel))[0]
    word = re.compile(r"\b" + re.escape(name) + r"\b")
    target = os.path.normpath(os.path.join(project, rel))
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            path = os.path.join(dp, fn)
            if not fn.endswith(".cs") or os.path.normpath(path) == target:
                continue
            try:
                if word.search(open(path, encoding="utf-8", errors="ignore").read()):
                    return False
            except OSError:
                continue
    return True


def drop_missing_type_files(project, errors):
    files = sorted({e[0] for e in errors if e[3] in ("CS0103", "CS0246")})
    dropped = []
    for rel in files:
        if not removable(project, rel):
            continue
        backup = os.path.join(project, "PatchBackup", "dropped", rel)
        os.makedirs(os.path.dirname(backup), exist_ok=True)
        for suffix in ("", ".meta"):
            src = os.path.join(project, rel + suffix)
            if os.path.exists(src):
                shutil.move(src, backup + suffix)
        dropped.append(rel)
    if dropped:
        print(f"✅ Tạm bỏ {len(dropped)} script thiếu kiểu (demo / không nơi nào dùng): "
              + ", ".join(os.path.basename(d) for d in dropped[:6]) + (" …" if len(dropped) > 6 else ""))
    return len(dropped)


def drop_codegen_registry(project, errors):
    """AssemblyTypeRegistry.cs do Unity.Entities tự sinh lúc build game gốc (ở đây là registry
    rỗng, không có system ECS nào); bản AssetRipper trích ra không khớp Entities hiện tại
    (CS0122/CS1510) → tạm bỏ các file trong CodeGeneratedRegistry/."""
    if not any("/CodeGeneratedRegistry/" in e[0] for e in errors):
        return 0
    dropped = []
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        if os.path.basename(dp) != "CodeGeneratedRegistry":
            continue
        for fn in fns:
            if not fn.endswith(".cs"):
                continue
            rel = os.path.relpath(os.path.join(dp, fn), project)
            backup = os.path.join(project, "PatchBackup", "dropped", rel)
            os.makedirs(os.path.dirname(backup), exist_ok=True)
            for suffix in ("", ".meta"):
                if os.path.exists(os.path.join(project, rel + suffix)):
                    shutil.move(os.path.join(project, rel + suffix), backup + suffix)
            dropped.append(rel)
    if dropped:
        print(f"✅ Tạm bỏ {len(dropped)} file registry do Entities tự sinh: " + ", ".join(os.path.basename(d) for d in dropped))
    return len(dropped)


WEBGL_CACHING_STUB = """// UnityEngine.Caching không có trong profile WebGL của Unity 6 (WebGL tự cache bằng IndexedDB).
// Chỉ định nghĩa cho bản player WebGL; Editor vẫn dùng UnityEngine.Caching thật.
#if UNITY_WEBGL && !UNITY_EDITOR
using UnityEngine;

public static class Caching
{
	public static bool ready => true;

	public static bool IsVersionCached(string url, Hash128 hash) => false;

	public static bool IsVersionCached(string url, int version) => false;

	public static bool ClearCache() => true;

	public static bool ClearCachedVersion(string assetBundleName, Hash128 hash) => true;
}
#endif
"""


def add_webgl_caching_stub(project, text):
    if not re.search(r"error CS0103: The name 'Caching' does not exist", text):
        return 0
    path = os.path.join(project, "Assets", "Scripts", "GameHubCompat", "WebGLCaching.cs")
    if os.path.exists(path):
        return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(WEBGL_CACHING_STUB)
    print("✅ Thêm lớp Caching rỗng cho WebGL (UnityEngine.Caching không có trên WebGL)")
    return 1


def main():
    project, log = os.path.abspath(sys.argv[1]), sys.argv[2]
    try:
        text = open(log, encoding="utf-8", errors="ignore").read()
    except OSError:
        return 1
    errors = sorted(set(ERROR.findall(text)))
    fixed = 0
    files = {}
    # Sửa từ cuối file lên để cột/dòng phía trước không bị lệch.
    for path, line_no, col, code, message in sorted(errors, key=lambda e: (e[0], -int(e[1]), -int(e[2]))):
        if code not in ("CS0104", "CS0165", "CS1061", "CS0592"):
            continue
        full = os.path.join(project, path)
        if full not in files:
            try:
                files[full] = open(full, encoding="utf-8-sig").read().split("\n")
            except OSError:
                continue
        lines = files[full]
        if int(line_no) > len(lines):
            continue
        if code == "CS0104" and fix_ambiguous(lines, int(line_no), int(col), message):
            fixed += 1
        elif code == "CS0165" and fix_unassigned(lines, int(line_no), message):
            fixed += 1
        elif code == "CS1061" and fix_extra_value(lines, int(line_no), int(col), message):
            fixed += 1
        elif code == "CS0592" and fix_orphan_attribute(lines, int(line_no)):
            fixed += 1
    for full, lines in files.items():
        open(full, "w", encoding="utf-8").write("\n".join(lines))
    if fixed:
        print(f"✅ Sửa {fixed} lỗi CS0104/CS0165/CS1061/CS0592 theo log build")
    fixed += fix_state_machines(project, errors)
    fixed += drop_missing_type_files(project, errors)
    fixed += drop_codegen_registry(project, errors)
    fixed += add_webgl_caching_stub(project, text)

    # UniTask cũ: thiếu hàm do bị cắt (CS0656), hoặc GetAwaiter(AsyncOperation) trùng
    # với UnityEngine.AsyncOperationAwaitableExtensions của Unity 2023.1+ (CS0121)
    # — UniTask 2.5 đã bỏ extension này trên Unity mới.
    if re.search(r"error CS0656: Missing compiler required member 'AsyncUniTask", text) or \
            re.search(r"error CS0121: [^\n]*Cysharp\.Threading\.Tasks\.UnityAsyncExtensions\.GetAwaiter", text):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "unity_unitask_full.py")
        if subprocess.run([sys.executable, script, project]).returncode == 0:
            fixed += 1
    return 0 if fixed else 1


if __name__ == "__main__":
    sys.exit(main())
