#!/usr/bin/env python3
"""Sinh "source" SideStore/AltStore chung cho mọi app trong apps/.

    python3 toolkit/sidestore_source.py [base-url] [--source-url URL]
    python3 toolkit/sidestore_source.py --print-base

Quét apps/*/xtool/*.ipa (bản build gần nhất của từng app). Kết quả trong thư mục
SOURCE_OUT (mặc định sidestore/):
    source.json            ← thêm URL này vào SideStore (1 lần, dùng cho mọi app)
    <App>.png              ← icon lấy từ IPA
    <App>-1.<N>.ipa        ← tên có version để SideStore không dùng bản cache cũ

base-url là nơi chứa các file trên: IP LAN (phục vụ bằng toolkit/serve_sidestore.sh)
hoặc URL GitHub Releases (do toolkit/publish_github.sh sinh ra, SOURCE_OUT=source).
--source-url chỉ định URL của chính source.json khi nó nằm khác base (vd raw.githubusercontent).
"""
import glob
import json
import os
import plistlib
import shutil
import socket
import sys
import zipfile
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, os.environ.get("SOURCE_OUT", "sidestore"))
PORT = int(os.environ.get("SIDESTORE_PORT", "8765"))
# Giữ identifier của source GameHub cũ: SideStore đã thêm source này, đổi
# identifier thì phải xoá source và thêm lại trên iPhone.
SOURCE_ID = "vn.vudv.gamehub.source"


def lan_ip():
    # Không gửi gói nào — chỉ hỏi kernel sẽ đi ra mạng bằng interface nào.
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.0.1", 9))
        return s.getsockname()[0]
    finally:
        s.close()


def app_entry(ipa, base, now):
    with zipfile.ZipFile(ipa) as z:
        app_dir = next(n for n in z.namelist()
                       if n.startswith("Payload/") and n.endswith(".app/Info.plist"))[:-len("Info.plist")]
        info = plistlib.loads(z.read(app_dir + "Info.plist"))
        icon = z.read(app_dir + "AppIcon60x60@2x.png")
    name = info.get("CFBundleDisplayName") or info["CFBundleName"]
    file_stem = name.replace(" ", "")
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]

    for old in glob.glob(os.path.join(OUT, f"{file_stem}-*.ipa")):
        os.remove(old)
    ipa_name = f"{file_stem}-{version}.ipa"
    shutil.copyfile(ipa, os.path.join(OUT, ipa_name))
    with open(os.path.join(OUT, f"{file_stem}.png"), "wb") as fh:
        fh.write(icon)

    size = os.path.getsize(ipa)
    download = f"{base}/{ipa_name}"
    return {
        "name": name,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "vudv",
        "subtitle": "Bản build từ máy tính",
        "localizedDescription": "Bản build mới nhất từ máy tính trong mạng nhà.",
        "iconURL": f"{base}/{file_stem}.png",
        "tintColor": "#738CFF",
        # Định dạng cũ (AltStore 1.x / SideStore cũ)
        "version": version,
        "versionDate": now.strftime("%Y-%m-%d"),
        "versionDescription": f"Build {build}",
        "downloadURL": download,
        "size": size,
        # Định dạng mới (AltStore 2.x / SideStore mới)
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": now.isoformat(timespec="seconds"),
            "localizedDescription": f"Build {build}",
            "downloadURL": download,
            "size": size,
        }],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }


def main():
    args = sys.argv[1:]
    if args == ["--print-base"]:
        print(f"http://{lan_ip()}:{PORT}")
        return
    positional = [a for a in args if not a.startswith("--")]
    base = positional[0] if positional else f"http://{lan_ip()}:{PORT}"
    source_url = f"{base}/source.json"
    if "--source-url" in args:
        source_url = args[args.index("--source-url") + 1]
    os.makedirs(OUT, exist_ok=True)
    now = datetime.now(timezone.utc)

    apps = []
    for app_dir in sorted(glob.glob(os.path.join(ROOT, "apps", "*"))):
        ipas = sorted(glob.glob(os.path.join(app_dir, "xtool", "*.ipa")), key=os.path.getmtime)
        if ipas:
            apps.append(app_entry(ipas[-1], base, now))

    source = {
        "name": "iOS apps (máy nhà)",
        "identifier": SOURCE_ID,
        "sourceURL": source_url,
        "apps": apps,
        "news": [],
    }
    with open(os.path.join(OUT, "source.json"), "w", encoding="utf-8") as fh:
        json.dump(source, fh, ensure_ascii=False, indent=2)
    listed = ", ".join(f"{a['name']} {a['version']}" for a in apps)
    print(f"✅ SideStore source: {source_url}  ({listed})")


if __name__ == "__main__":
    main()
