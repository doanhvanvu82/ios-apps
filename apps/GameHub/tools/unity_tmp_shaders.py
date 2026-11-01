#!/usr/bin/env python3
"""Thay shader TextMeshPro dummy của AssetRipper bằng shader thật trong com.unity.ugui.

AssetRipper không dịch ngược được shader nên xuất bản dummy (`//DummyShaderTextExporter`) chỉ
`return _MainTex.Sample(...)`. Atlas font có RGB = 0 → mọi ký tự TMP thành khối đen đặc (vd
NTR_Kazoku: chữ menu). Giữ nguyên .meta (GUID) để material vẫn trỏ đúng; chỉ ghi đè nội dung
.shader theo tên shader và chép các file .cginc/.hlsl mà shader include.

Dùng: unity_tmp_shaders.py <ExportedProject> <Unity/Editor>
"""
import os
import re
import sys
import tarfile

PACKAGE = os.path.join("Data", "Resources", "PackageManager", "BuiltInPackages", "com.unity.ugui",
                       "Package Resources", "TMP Essential Resources.unitypackage")
SHADER_DIR = "Assets/TextMesh Pro/Shaders/"
NAME = re.compile(r'^\s*Shader\s+"([^"]+)"', re.M)


def package_files(unity):
    """{tên file: nội dung bytes} của các .shader/.cginc/.hlsl trong gói."""
    files = {}
    with tarfile.open(os.path.join(unity, PACKAGE)) as tar:
        entries = {}
        for m in tar.getmembers():
            if m.isfile():
                folder, _, leaf = m.name.removeprefix("./").partition("/")
                entries.setdefault(folder, {})[leaf] = m
        for parts in entries.values():
            if "pathname" not in parts or "asset" not in parts:
                continue
            path = tar.extractfile(parts["pathname"]).read().decode().split("\n")[0].strip()
            if path.startswith(SHADER_DIR) and path.endswith((".shader", ".cginc", ".hlsl")):
                files[path[len(SHADER_DIR):]] = tar.extractfile(parts["asset"]).read()
    return files


def main():
    project, unity = os.path.abspath(sys.argv[1]), sys.argv[2]
    shaders = os.path.join(project, "Assets")
    real = {}
    files = package_files(unity)
    for leaf, data in files.items():
        if leaf.endswith(".shader"):
            m = NAME.search(data.decode("utf-8", "ignore"))
            if m:
                real[m.group(1)] = data

    fixed = 0
    for dp, _, fns in os.walk(shaders):
        for fn in fns:
            if not fn.endswith(".shader"):
                continue
            path = os.path.join(dp, fn)
            text = open(path, encoding="utf-8", errors="ignore").read()
            m = NAME.search(text)
            if "DummyShaderTextExporter" not in text or not m or m.group(1) not in real:
                continue
            for leaf, data in files.items():
                if leaf.endswith((".cginc", ".hlsl")):
                    with open(os.path.join(dp, leaf), "wb") as f:
                        f.write(data)
            with open(path + ".tmp", "wb") as f:
                f.write(real[m.group(1)])
            os.replace(path + ".tmp", path)
            fixed += 1
    if fixed:
        print(f"✅ TMP: thay {fixed} shader dummy bằng shader TextMeshPro thật")


if __name__ == "__main__":
    main()
