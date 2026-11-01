#!/usr/bin/env python3
"""Đổi tham chiếu script UI/TMP của game sang gói com.unity.ugui của Unity 6.

unity_normalize_project.py xoá UnityEngine.UI.dll và Unity.TextMeshPro.dll của game (trùng với
com.unity.ugui). Nhưng scene/prefab trỏ script bằng {fileID: <hash kiểu>, guid: <guid DLL>} →
sau khi xoá DLL, Text/Image/Button/TMP_Text… thành "The referenced script on this Behaviour
is missing!" (UI mất hết). Đổi sang {fileID: 11500000, guid: <guid tệp .cs của gói>}.

Phải chạy TRƯỚC unity_normalize_project.py (cần .meta của DLL để biết guid).
Dùng: unity_ugui_script_refs.py <ExportedProject> <thư mục Unity Editor>
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("isp", os.path.join(HERE, "unity_inputsystem_package.py"))
isp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isp)

DLLS = (
    "UnityEngine.UI.dll", "Unity.TextMeshPro.dll",
    "Unity.RenderPipelines.Core.Runtime.dll", "Unity.RenderPipelines.Universal.Runtime.dll",
    "Unity.RenderPipelines.Universal.2D.Runtime.dll", "Unity.RenderPipelines.Universal.Config.Runtime.dll",
)
PACKAGES = ("com.unity.ugui", "com.unity.render-pipelines.universal", "com.unity.render-pipelines.core")


def main():
    project, unity = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    plugins = os.path.join(project, "Assets", "Plugins")
    guids = {}
    for dll in DLLS:
        meta = os.path.join(plugins, dll + ".meta")
        if os.path.isfile(meta):
            guids[re.search(r"^guid:\s*(\w+)", open(meta).read(), re.M).group(1)] = dll
    if not guids:
        return
    builtin = os.path.join(unity, "Data", "Resources", "PackageManager", "BuiltInPackages")
    pkgs = [os.path.join(builtin, name) for name in PACKAGES]
    if not all(os.path.isdir(pkg) for pkg in pkgs):
        print("⚠️  ugui/URP: thiếu package trong Unity — giữ nguyên tham chiếu.")
        return
    mapping = {}
    for pkg in pkgs:
        mapping.update(isp.package_scripts(pkg))
    ref = re.compile(r"\{fileID: (-?\d+), guid: (" + "|".join(guids) + r"), type: 3\}")
    fixed = missing = 0
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            if not fn.endswith(isp.ASSET_EXT):
                continue
            path = os.path.join(dp, fn)
            text = open(path, encoding="utf-8", errors="ignore").read()
            if not ref.search(text):
                continue

            def sub(m):
                nonlocal fixed, missing
                guid = mapping.get(int(m.group(1)))
                if not guid:
                    missing += 1
                    return m.group(0)
                fixed += 1
                return "{fileID: 11500000, guid: " + guid + ", type: 3}"
            open(path, "w", encoding="utf-8").write(ref.sub(sub, text))
    print(f"✅ ugui: đổi {fixed} tham chiếu script UI/TMP/URP" + (f" ({missing} không khớp)" if missing else ""))


if __name__ == "__main__":
    main()
