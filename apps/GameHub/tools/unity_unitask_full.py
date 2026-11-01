#!/usr/bin/env python3
"""Thay UniTask.dll bị cắt (managed stripping) bằng gói UniTask chính thức.

    unity_unitask_full.py <project-dir>

Bản build Mono của game thường bật managed stripping: UniTask.dll trong
`*_Data/Managed` mất các hàm mà mã game không gọi trực tiếp, vd
`AsyncUniTaskMethodBuilder<T>.AwaitOnCompleted`. AssetRipper dịch ngược
Assembly-CSharp thành mã nguồn có `async UniTask` → biên dịch lại cần đúng các
hàm đã bị cắt → lỗi CS0656 "Missing compiler required member".

Gói chính thức (Cysharp/UniTask, MIT) có cùng tên assembly `UniTask`, nên DLL
khác của game tham chiếu tới nó (vd Naninovel) vẫn khớp. unity_build_webgl.sh
gọi script này khi log build có lỗi CS0656 với AsyncUniTask…, rồi build lại.
"""
import json
import os
import re
import shutil
import sys

PACKAGE = "com.cysharp.unitask"
URL = "https://github.com/Cysharp/UniTask.git?path=src/UniTask/Assets/Plugins/UniTask#2.5.11"
# Các assembly gói chính thức cũng cung cấp — phải bỏ bản cũ để không trùng tên.
ASSEMBLIES = ("UniTask", "UniTask.Addressables", "UniTask.DOTween", "UniTask.Linq", "UniTask.TextMeshPro")


def add_webgl_define(project, define):
    """Thêm scripting define cho WebGL trong ProjectSettings.asset."""
    path = os.path.join(project, "ProjectSettings", "ProjectSettings.asset")
    text = open(path, encoding="utf-8").read()
    if re.search(r"^  scriptingDefineSymbols: \{\}$", text, re.M):
        text = re.sub(r"^  scriptingDefineSymbols: \{\}$", f"  scriptingDefineSymbols:\n    WebGL: {define}", text, count=1, flags=re.M)
    elif re.search(r"^    WebGL: .*$", text, re.M):
        text = re.sub(r"^(    WebGL: .*)$", rf"\1;{define}", text, count=1, flags=re.M)
    else:
        text = re.sub(r"^(  scriptingDefineSymbols:)$", rf"\1\n    WebGL: {define}", text, count=1, flags=re.M)
    open(path, "w", encoding="utf-8").write(text)


def main():
    project = os.path.abspath(sys.argv[1])
    manifest_path = os.path.join(project, "Packages", "manifest.json")
    manifest = json.load(open(manifest_path))
    deps = manifest.setdefault("dependencies", {})
    if PACKAGE in deps:
        print("✅ UniTask: đã dùng gói chính thức — bỏ qua.")
        return 1

    backup = os.path.join(project, "PatchBackup", "UniTask")
    os.makedirs(backup, exist_ok=True)
    moved = []
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            base = fn[:-len(".dll.meta")] if fn.endswith(".dll.meta") else fn[:-len(".dll")] if fn.endswith(".dll") else None
            if base in ASSEMBLIES:
                shutil.move(os.path.join(dp, fn), os.path.join(backup, fn))
                if fn.endswith(".dll"):
                    moved.append(fn)
    if not moved:
        print("⚠️  UniTask: không thấy UniTask.dll trong Assets — bỏ qua.")
        return 1

    # DOTween/Addressables của game là DLL (không phải gói UPM) nên versionDefines
    # của UniTask không bật → bật tay, nhưng chỉ khi game thật sự có thư viện đó
    # (có game kèm UniTask.DOTween.dll rỗng mà không có DOTween).
    dlls = {fn for _, _, fns in os.walk(os.path.join(project, "Assets")) for fn in fns if fn.endswith(".dll")}
    if "UniTask.DOTween.dll" in moved and "DOTween.dll" in dlls:
        add_webgl_define(project, "UNITASK_DOTWEEN_SUPPORT")
    if "UniTask.Addressables.dll" in moved and "Unity.Addressables.dll" in dlls:
        add_webgl_define(project, "UNITASK_ADDRESSABLE_SUPPORT")

    deps[PACKAGE] = URL
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"✅ UniTask: thay {', '.join(moved)} (bản bị cắt) bằng gói chính thức 2.5.11 — backup ở PatchBackup/UniTask/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
