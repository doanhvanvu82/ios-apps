#!/usr/bin/env bash
#
# Chép log chẩn đoán của một app từ iPhone cắm USB về máy: Documents/Logs của app → .state/logs/<bundleID>/.
# App phải bật UIFileSharingEnabled trong Info.plist (vd apps/AdsBlocker, log ghi bởi AppLog.swift).
#
#   toolkit/pull_app_logs.sh vn.vudv.adsblocker
#
set -euo pipefail
BUNDLE=${1:?"Thiếu bundle ID, vd: $0 vn.vudv.adsblocker"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/.state/logs/$BUNDLE"

command -v ifuse >/dev/null || { echo "Cần ifuse: sudo apt install ifuse"; exit 1; }
if ! idevicepair validate >/dev/null 2>&1; then
    idevicepair pair || true
    echo "Mở khoá iPhone, bấm \"Tin cậy\" máy tính này rồi chạy lại."
    exit 1
fi

# Công cụ cài ký lại với bundle ID có thêm hậu tố team ID (vn.vudv.adsblocker.64MBZK65W9) → tìm theo tiền tố.
INSTALLED=$(ifuse --list-apps | cut -d, -f1 | grep -E "^${BUNDLE//./\\.}(\.[A-Z0-9]+)?$" | head -1) || true
[ -n "$INSTALLED" ] || { echo "Không thấy app $BUNDLE có bật chia sẻ tệp (UIFileSharingEnabled) trên iPhone."; exit 1; }

MNT=$(mktemp -d)
trap 'fusermount -u "$MNT" 2>/dev/null || true; rmdir "$MNT"' EXIT
ifuse --documents "$INSTALLED" "$MNT"
mkdir -p "$OUT"
cp -r "$MNT/Logs/." "$OUT/"
echo "✅ Log → $OUT"
ls -la "$OUT"
