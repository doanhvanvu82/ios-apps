#!/usr/bin/env bash
#
# Build GameHub thành file .ipa trên Linux (pipeline chung: ../../toolkit/build_app.sh).
#
#   ./build.sh          -> build (incremental)
#   ./build.sh clean    -> xóa toàn bộ build cache rồi build lại từ đầu
#
# Mỗi lần build còn cập nhật source AltStore chung (../../sidestore/) và bật
# server LAN → trên iPhone mở Ksign, tải/cài GameHub (không cần chép IPA).
#
# Kết quả: ./xtool/GameHub.ipa
#
set -euo pipefail

cd "$(dirname "$0")"
TOOLKIT=../../toolkit

# Icon riêng của GameHub (vẽ bằng Pillow) → tools/icon_gen/AppIcon1024.png.
python3 tools/gen_icon.py >/dev/null

# Địa chỉ server LAN (toolkit/dev_server.py) cho nút "Gửi về máy tính" ở màn Log.
DEV_SERVER=$(python3 "$TOOLKIT/sidestore_source.py" --print-base)
python3 - "$DEV_SERVER" <<'PY'
import plistlib, sys
with open("Info.plist", "rb") as f:
    pl = plistlib.load(f)
pl["GameHubDevServer"] = sys.argv[1]
pl["NSLocalNetworkUsageDescription"] = "Gửi log về máy tính trong mạng nhà để chẩn đoán lỗi."
with open("Info.plist", "wb") as f:
    plistlib.dump(pl, f)
PY
echo "→ Dev server: $DEV_SERVER"

APP_ICON=tools/icon_gen/AppIcon1024.png exec "$TOOLKIT/build_app.sh" . "$@"
