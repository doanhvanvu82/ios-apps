#!/usr/bin/env bash
#
# Chèn app icon vào IPA sau khi build.
#
#   toolkit/patch_icon.sh <file.ipa> <icon-1024.png>
#
# SwiftPM + xtool không sinh icon (cần Xcode asset catalog), nên script này:
#   1. Thu nhỏ icon 1024×1024 thành 120×120 (iPhone) và 152×152 (iPad) bằng Pillow.
#   2. Mở IPA, chèn file icon + cập nhật Info.plist (CFBundleIcons).
#
# Chạy tự động trong build_app.sh.
#
set -euo pipefail

IPA="$(realpath "${1:?Cách dùng: patch_icon.sh <file.ipa> <icon-1024.png>}")"
ICON="$(realpath "${2:?Thiếu icon 1024×1024}")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Giải nén IPA.
unzip -q "$IPA" -d "$WORK"
APP="$(ls -d "$WORK"/Payload/*.app)"

# 2. Sinh icon vào bundle + cập nhật Info.plist.
python3 - "$ICON" "$APP" <<'PY'
import os
import plistlib
import sys

from PIL import Image

icon, app = sys.argv[1], sys.argv[2]
src = Image.open(icon).convert("RGBA")
src.resize((120, 120), Image.LANCZOS).save(os.path.join(app, "AppIcon60x60@2x.png"))
src.resize((152, 152), Image.LANCZOS).save(os.path.join(app, "AppIcon76x76@2x~ipad.png"))

path = os.path.join(app, "Info.plist")
with open(path, "rb") as f:
    pl = plistlib.load(f)

primary = {
    "CFBundleIconFiles": ["AppIcon60x60"],
    "CFBundleIconName": "AppIcon",
}
primary_ipad = {
    "CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76"],
    "CFBundleIconName": "AppIcon",
}
pl.setdefault("CFBundleIcons", {})["CFBundlePrimaryIcon"] = primary
pl.setdefault("CFBundleIcons~ipad", {})["CFBundlePrimaryIcon"] = primary_ipad

with open(path, "wb") as f:
    plistlib.dump(pl, f)
print("✅ Info.plist có CFBundleIcons")
PY

# 3. Đóng gói lại IPA.
cd "$WORK"
rm -f "$IPA"
zip -qr "$IPA" Payload
cd - >/dev/null

echo "✅ Icon đã chèn vào $IPA"
