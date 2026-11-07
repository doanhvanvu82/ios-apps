#!/usr/bin/env bash
#
# Build MyDrive thành file .ipa trên Linux (pipeline chung: ../../toolkit/build_app.sh).
#
#   ./build.sh          -> build (incremental)
#   ./build.sh clean    -> xóa toàn bộ build cache rồi build lại từ đầu
#
# Mỗi lần build còn cập nhật source AltStore chung (../../sidestore/) và bật
# server LAN → trên iPhone mở Ksign, tải/cài MyDrive (không cần chép IPA).
#
# Yêu cầu riêng của MyDrive: OAuth Client ID (xem oauth_client.example.txt).
# build.sh đọc oauth_client.txt (nếu có) rồi ghi:
#   - MyDriveOAuthClientID vào Info.plist (app đọc khi đăng nhập);
#   - CFBundleURLTypes     = scheme reversed client ID (bắt buộc có từ lúc build —
#     iOS không cho đăng ký URL scheme lúc chạy; không có client ID thì app vẫn
#     build/cài được nhưng chưa đăng nhập được).
#
# Kết quả: ./xtool/MyDrive.ipa
#
set -euo pipefail

cd "$(dirname "$0")"
TOOLKIT=../../toolkit

# Icon riêng của MyDrive (vẽ bằng Pillow) → tools/icon_gen/AppIcon1024.png.
python3 tools/gen_icon.py >/dev/null

if [ -f oauth_client.txt ]; then
    CLIENT_ID=$(tr -d ' \t\r\n' < oauth_client.txt)
    if [ -z "$CLIENT_ID" ]; then
        echo "⚠️ oauth_client.txt rỗng — app sẽ build nhưng chưa đăng nhập được Google." >&2
    else
        # Điền client ID + URL scheme vào Info.plist (đọc từ file thường,
        # không giữ trong git để tránh lộ).
        python3 - "$CLIENT_ID" <<'PY'
import plistlib, sys
client_id = sys.argv[1]
with open("Info.plist", "rb") as f:
    pl = plistlib.load(f)
pl["MyDriveOAuthClientID"] = client_id
# Google iOS client dùng scheme là client ID đảo ngược theo THÀNH PHẦN ngăn cách
# bởi dấu chấm (vd 123-abc.apps.googleusercontent.com → com.googleusercontent.apps.123-abc).
# Phải khớp GoogleAuthService.reversedClientID trong app.
scheme = ".".join(reversed(client_id.split(".")))
pl["CFBundleURLTypes"] = [{
    "CFBundleURLName": "vn.vudv.mydrive.oauth",
    "CFBundleURLSchemes": [scheme],
}]
with open("Info.plist", "wb") as f:
    plistlib.dump(pl, f)
print(f"→ OAuth client ID: {client_id[:12]}… (scheme đăng ký)")
PY
    fi
else
    echo "⚠️ Chưa có oauth_client.txt — app sẽ build nhưng chưa đăng nhập được Google." >&2
    echo "   Xem oauth_client.example.txt và SETUP.md để tạo Client ID." >&2
fi

APP_ICON=tools/icon_gen/AppIcon1024.png exec "$TOOLKIT/build_app.sh" . "$@"
