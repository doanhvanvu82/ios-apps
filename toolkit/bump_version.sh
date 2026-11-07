#!/usr/bin/env bash
#
# Đánh số version cho một app.
#
#   toolkit/bump_version.sh <thư-mục-app>
#
# File <app>/VERSION lưu build number. `build_app.sh` gọi script này TRƯỚC
# khi build để:
#   1. Tăng VERSION lên 1 (mỗi lần build = 1 bản mới, không bao giờ trùng —
#      Ksign chỉ nhận cập nhật khi version đổi).
#   2. Ghi CFBundleShortVersionString + CFBundleVersion vào <app>/Info.plist và
#      plist của app extension (<app>/*-Info.plist) — iOS đòi version
#      extension trùng app chứa.
#
# Version hiển thị: major.minor với minor 2 chữ số, tối đa 99:
#   build 99 → 1.99, build 100 → 2.00, build 199 → 2.99, build 200 → 3.00.
#
set -euo pipefail

APP_DIR="${1:?Cách dùng: bump_version.sh <thư-mục-app>}"
VERSION_FILE="$APP_DIR/VERSION"

# 1. Tăng build number.
CURRENT=$(cat "$VERSION_FILE" 2>/dev/null || echo 0)
NEXT=$((CURRENT + 1))
echo "$NEXT" > "$VERSION_FILE"

# 2. Ghi vào Info.plist (idempotent — xoá key cũ rồi thêm mới).
python3 - "$NEXT" "$APP_DIR"/Info.plist "$APP_DIR"/*-Info.plist <<'PY'
import os
import plistlib
import sys

build, paths = int(sys.argv[1]), [p for p in sys.argv[2:] if os.path.isfile(p)]
# Version hiển thị: major.minor, minor luôn 2 chữ số và tối đa 99.
# build 99 → 1.99, build 100 → 2.00, build 199 → 2.99, build 200 → 3.00.
major = 1 + build // 100
minor = build % 100
for path in paths:
    with open(path, "rb") as f:
        pl = plistlib.load(f)

    pl["CFBundleShortVersionString"] = f"{major}.{minor:02d}"
    pl["CFBundleVersion"] = str(build)

    with open(path, "wb") as f:
        plistlib.dump(pl, f)
print(f"✅ Version {major}.{minor:02d} (build {build}) → " + ", ".join(os.path.basename(p) for p in paths))
PY
