#!/usr/bin/env python3
"""Thay Unity.InputSystem*.dll cũ của game bằng gói com.unity.inputsystem của Unity 6.

DLL dựng cho Unity 2022/2023 dùng kiểu engine đã đổi (vd
UnityEngine.InputForUI.NavigationDeviceType) → IL2CPP sinh C++ lỗi
"no viable conversion from returned value of type 'int' to … NavigationDeviceType".

Gói được nhúng vào Packages/ (giải từ tgz đi kèm Unity). Asset tham chiếu script
trong DLL bằng {fileID: <hash kiểu>, guid: <guid DLL>}; đổi sang
{fileID: 11500000, guid: <guid tệp .cs của gói>} để component không bị mất.

Dùng: unity_inputsystem_package.py <ExportedProject> <thư mục Unity Editor>
"""
import glob
import os
import re
import shutil
import struct
import sys
import tarfile

DLLS = ("Unity.InputSystem.dll", "Unity.InputSystem.ForUI.dll")
ASSET_EXT = (".unity", ".prefab", ".asset", ".mat", ".controller", ".anim", ".playable", ".inputactions")


def md4(data):
    def f(x, y, z): return (x & y) | (~x & z)
    def g(x, y, z): return (x & y) | (x & z) | (y & z)
    def h(x, y, z): return x ^ y ^ z
    def rol(x, n): return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF
    msg = data + b"\x80" + b"\0" * ((55 - len(data)) % 64) + struct.pack("<Q", len(data) * 8)
    a, b, c, d = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476
    for off in range(0, len(msg), 64):
        x = struct.unpack("<16I", msg[off:off + 64])
        aa, bb, cc, dd = a, b, c, d
        for i in range(16):
            k, s = i, (3, 7, 11, 19)[i % 4]
            a = rol((a + f(b, c, d) + x[k]) & 0xFFFFFFFF, s); a, b, c, d = d, a, b, c
        for i in range(16):
            k, s = (i % 4) * 4 + i // 4, (3, 5, 9, 13)[i % 4]
            a = rol((a + g(b, c, d) + x[k] + 0x5A827999) & 0xFFFFFFFF, s); a, b, c, d = d, a, b, c
        for i in range(16):
            k, s = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15)[i], (3, 9, 11, 15)[i % 4]
            a = rol((a + h(b, c, d) + x[k] + 0x6ED9EBA1) & 0xFFFFFFFF, s); a, b, c, d = d, a, b, c
        a, b, c, d = (a + aa) & 0xFFFFFFFF, (b + bb) & 0xFFFFFFFF, (c + cc) & 0xFFFFFFFF, (d + dd) & 0xFFFFFFFF
    return struct.pack("<4I", a, b, c, d)


def script_file_id(namespace, name):
    """fileID Unity gán cho MonoScript của kiểu `name` nằm trong một DLL."""
    return struct.unpack("<i", md4(b"s\0\0\0" + (namespace + name).encode())[:4])[0]


def package_scripts(package_dir):
    """fileID (theo DLL) → guid của tệp .cs khai báo class cùng tên tệp."""
    ns_re = re.compile(r"^\s*namespace\s+([\w.]+)", re.M)
    mapping = {}
    for cs in glob.glob(os.path.join(package_dir, "**", "*.cs"), recursive=True):
        meta = cs + ".meta"
        if not os.path.isfile(meta):
            continue
        name = os.path.basename(cs)[:-3]
        src = open(cs, encoding="utf-8", errors="ignore").read()
        if not re.search(r"\b(class|struct)\s+" + re.escape(name) + r"\b", src):
            continue
        m = ns_re.search(src)
        guid = re.search(r"^guid:\s*(\w+)", open(meta).read(), re.M).group(1)
        mapping[script_file_id(m.group(1) if m else "", name)] = guid
    return mapping


def main():
    project, unity = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    dlls = [p for p in glob.glob(os.path.join(project, "Assets", "**", "*.dll"), recursive=True)
            if os.path.basename(p) in DLLS]
    if not dlls:
        return
    tgz = sorted(glob.glob(os.path.join(unity, "Data", "Resources", "PackageManager", "Editor", "com.unity.inputsystem-*.tgz")))
    if not tgz:
        print("⚠️  InputSystem: không thấy gói com.unity.inputsystem trong Unity — giữ DLL.")
        return
    pkg = os.path.join(project, "Packages", "com.unity.inputsystem")
    if not os.path.isdir(pkg):
        tmp = pkg + ".tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        with tarfile.open(tgz[-1]) as tf:
            tf.extractall(tmp, filter="data")
        os.replace(os.path.join(tmp, "package"), pkg)
        shutil.rmtree(tmp, ignore_errors=True)
    mapping = package_scripts(pkg)

    dll_guids = {}
    backup = os.path.join(project, "PatchBackup", "inputsystem")
    os.makedirs(backup, exist_ok=True)
    for dll in dlls:
        meta = dll + ".meta"
        if os.path.isfile(meta):
            dll_guids[re.search(r"^guid:\s*(\w+)", open(meta).read(), re.M).group(1)] = os.path.basename(dll)
        for path in (dll, meta):
            if os.path.exists(path):
                shutil.move(path, os.path.join(backup, os.path.basename(path)))

    ref = re.compile(r"\{fileID: (-?\d+), guid: (" + "|".join(dll_guids) + r"), type: 3\}")
    fixed = missing = 0
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            if not fn.endswith(ASSET_EXT):
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
    print(f"✅ InputSystem: thay {', '.join(dll_guids.values())} bằng gói {os.path.basename(tgz[-1])[:-4]}, "
          f"đổi {fixed} tham chiếu script" + (f" ({missing} không khớp)" if missing else ""))


if __name__ == "__main__":
    main()
