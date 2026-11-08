#!/usr/bin/env python3
"""Sinh "source" AltStore (Ksign đọc được) chung cho mọi app trong apps/ + mods/.

    python3 toolkit/sidestore_source.py [base-url] [--source-url URL]
    python3 toolkit/sidestore_source.py --print-base

Quét apps/*/xtool/*.ipa + mods/*/out/*.ipa (bản build gần nhất của từng mục). Kết quả trong thư mục
SOURCE_OUT (mặc định sidestore/):
    source.json            ← thêm URL này vào Ksign (1 lần, dùng cho mọi app)
    <App>.png              ← icon lấy từ IPA
    <App>-1.<N>.ipa        ← tên có version để không dùng bản cache cũ

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
# Giữ identifier của source cũ: client đã thêm source này, đổi identifier thì
# phải xoá source và thêm lại trên iPhone.
SOURCE_ID = "vn.vudv.gamehub.source"


def lan_ip():
    # Không gửi gói nào — chỉ hỏi kernel sẽ đi ra mạng bằng interface nào.
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.0.1", 9))
        return s.getsockname()[0]
    finally:
        s.close()


ICON_CANDIDATES = (
    "AppIcon60x60@3x.png",
    "AppIcon60x60@2x.png",
    "AppIcon76x76@2x~ipad.png",
    "Icon-60@3x.png",
    "Icon-60@2x.png",
    "icon1@3x.png",
    "icon1@2x.png",
    "icon1.png",
    "AppIcon.png",
)


def read_icon(z, app_dir, names):
    for name in ICON_CANDIDATES:
        if app_dir + name in names:
            return z.read(app_dir + name)
    # App dùng asset catalog nhưng có icon rời (vd YouTube: icon1/2/3@Nx).
    # Ưu tiên bản @3x, rồi @2x, rồi bản thường; sắp xếp để kết quả ổn định.
    loose = sorted(n for n in names
                   if n.startswith(app_dir) and "/" not in n[len(app_dir):]
                   and "icon" in n.lower() and n.endswith(".png"))
    for suffix in ("@3x.png", "@2x.png", ".png"):
        for name in loose:
            if name.endswith(suffix):
                return z.read(name)
    return None


def app_entry(ipa, base, now):
    with zipfile.ZipFile(ipa) as z:
        names = set(z.namelist())
        app_dir = next(n for n in z.namelist()
                       if n.startswith("Payload/") and n.endswith(".app/Info.plist"))[:-len("Info.plist")]
        info = plistlib.loads(z.read(app_dir + "Info.plist"))
        icon = read_icon(z, app_dir, names)
    name = info.get("CFBundleDisplayName") or info["CFBundleName"]
    file_stem = name.replace(" ", "")
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]

    for old in glob.glob(os.path.join(OUT, f"{file_stem}-*.ipa")):
        os.remove(old)
    # Mod giữ nguyên version app (vd YouTube 21.44.4) và chỉ tăng build — thêm
    # build vào tên file để Ksign không dùng cache bản cũ.
    suffix = version if str(build) == str(version) else f"{version}-{build}"
    ipa_name = f"{file_stem}-{suffix}.ipa"
    shutil.copyfile(ipa, os.path.join(OUT, ipa_name))
    if icon:
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
        "iconURL": f"{base}/{file_stem}.png" if icon else "",
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


def collect_ipas():
    """IPA cần đưa vào source: apps/*/xtool/*.ipa + mods/*/out/*.ipa.

    --dist DIR (hoặc DIST_DIR) thay cho quét repo — dùng khi CI tải artifact về
    một thư mục (có thể lồng nhau: apps/<App>/xtool/, mods/<mod>/out/).
    """
    dist = os.environ.get("DIST_DIR")
    args = sys.argv[1:]
    if "--dist" in args:
        dist = args[args.index("--dist") + 1]
    if dist:
        return sorted(glob.glob(os.path.join(dist, "**", "*.ipa"), recursive=True),
                      key=os.path.getmtime)

    excluded = set()
    exclude_file = os.path.join(ROOT, "build-exclude.txt")
    try:
        with open(exclude_file, encoding="utf-8") as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    excluded.add(line)
    except FileNotFoundError:
        pass

    keep_mods = bool(os.environ.get("SOURCE_KEEP_MODS"))
    ipas = []
    areas = ("apps", "mods")
    for area in areas:
        if area == "mods" and os.environ.get("SOURCE_NO_MODS"):
            continue
        for entry in sorted(glob.glob(os.path.join(ROOT, area, "*"))):
            base = os.path.basename(entry)
            rel = f"{area}/{base}"
            # Tôn trọng build-exclude.txt: mục không build thì không có trong source.
            if (base in excluded or rel in excluded) and not (keep_mods and area == "mods"):
                continue
            for sub in ("xtool", "out"):
                found = sorted(glob.glob(os.path.join(entry, sub, "*.ipa")),
                               key=os.path.getmtime)
                if found:
                    ipas.append(found[-1])
                    break
    return ipas


def main():
    args = sys.argv[1:]
    if args == ["--print-base"]:
        print(f"http://{lan_ip()}:{PORT}")
        return
    positional = [a for a in args if not a.startswith("--")]
    # Bỏ giá trị đi kèm --dist/--source-url/--merge-from khỏi danh sách positional.
    skip = set()
    for name in ("--dist", "--source-url", "--merge-from"):
        if name in args:
            i = args.index(name)
            skip.add(i)
            skip.add(i + 1)
    positional = [a for i, a in enumerate(args) if not a.startswith("--") and i not in skip]
    base = positional[0] if positional else f"http://{lan_ip()}:{PORT}"
    source_url = f"{base}/source.json"
    if "--source-url" in args:
        source_url = args[args.index("--source-url") + 1]
    os.makedirs(OUT, exist_ok=True)
    now = datetime.now(timezone.utc)

    apps = []
    for ipa in collect_ipas():
        apps.append(app_entry(ipa, base, now))

    # Danh sách app vừa build (trước khi gộp) — publish dùng để chỉ dọn asset
    # của đúng những app này, không đụng app khác.
    with open(os.path.join(OUT, ".built-apps.json"), "w", encoding="utf-8") as fh:
        json.dump(apps, fh, ensure_ascii=False)

    built_count = len(apps)
    merge_from = None
    if "--merge-from" in args:
        merge_from = args[args.index("--merge-from") + 1]
    if merge_from:
        # Publish một mục (scope/only) không được làm mất app khác khỏi source:
        # giữ nguyên entry cũ của app không nằm trong lần build này.
        with open(merge_from, encoding="utf-8") as fh:
            old = json.load(fh)
        new_by_id = {a["bundleIdentifier"]: a for a in apps}
        merged = []
        for a in old.get("apps", []):
            merged.append(new_by_id.pop(a.get("bundleIdentifier"), a))
        merged.extend(new_by_id.values())
        print(f"→ Gộp từ {os.path.basename(merge_from)}: giữ {len(merged) - built_count} mục cũ.")
        apps = merged

    # Tên source: GitHub publish dùng "iOS apps"; source LAN giữ nhãn máy nhà
    # (để phân biệt 2 source trên Ksign).
    source_name = os.environ.get("SOURCE_NAME", "iOS apps (máy nhà)")
    source = {
        "name": source_name,
        "identifier": SOURCE_ID,
        "sourceURL": source_url,
        "apps": apps,
        "news": [],
    }
    with open(os.path.join(OUT, "source.json"), "w", encoding="utf-8") as fh:
        json.dump(source, fh, ensure_ascii=False, indent=2)
    listed = ", ".join(f"{a['name']} {a['version']}" for a in apps)
    print(f"✅ Source Ksign: {source_url}  ({listed})")
    print(f"   build mới: {built_count}, tổng: {len(apps)}")


if __name__ == "__main__":
    main()
