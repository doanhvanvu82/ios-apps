#!/usr/bin/env bash
#
# Build một app iOS (SwiftPM + xtool) thành file .ipa trên Linux, rồi đưa lên
# source SideStore chung (../sidestore) và bật server LAN.
#
#   toolkit/build_app.sh <thư-mục-app>          -> build (incremental)
#   toolkit/build_app.sh <thư-mục-app> clean    -> xóa build cache rồi build lại từ đầu
#
# App cần có: Package.swift, xtool.yml, Info.plist, VERSION và icon 1024×1024
# ở <app>/AppIcon.png (đổi bằng biến APP_ICON).
#
# Kết quả: <app>/xtool/<Product>.ipa + sidestore/source.json (liệt kê mọi app).
#
set -euo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${1:?Cách dùng: build_app.sh <thư-mục-app> [clean]}" && pwd)"
MODE="${2:-}"
cd "$APP_DIR"

# ---------------------------------------------------------------------------
# 1. Toolchain
#
# Xcode 27.1 (SDK Darwin) đòi hỏi clang ≥ 22. Bản release swift.org mới nhất là
# 6.4.1 (clang 21) nên không đủ — phải dùng development snapshot (clang 23).
# ---------------------------------------------------------------------------
TOOLCHAIN="${IOS_TOOLCHAIN:-$HOME/swift-dev}"
if [ ! -x "$TOOLCHAIN/usr/bin/swiftc" ]; then
    echo "❌ Không tìm thấy Swift toolchain tại $TOOLCHAIN" >&2
    echo "   Đặt IOS_TOOLCHAIN=/path/to/swift để chỉ định toolchain khác." >&2
    exit 1
fi
export PATH="$TOOLCHAIN/usr/bin:$PATH"
echo "→ Toolchain: $(swiftc --version | head -1)"

# ---------------------------------------------------------------------------
# 2. Đồng bộ clang resource dir của SDK với toolchain
#
# Khi `xtool sdk install` chạy, nó copy thư mục `clang/include` của toolchain
# lúc đó vào trong SDK. Nếu toolchain đã đổi (vd: 6.0.3 -> 6.5-dev) mà
# không sync lại, các header của clang cũ sẽ gây:
#   "module '_c_standard_library_obsolete' requires feature
#    'found_incompatible_headers__check_search_paths'"
# và "cyclic dependency in module '_Builtin_float'".
# ---------------------------------------------------------------------------
SDK_BUNDLE="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
SDK_CLANG_INCLUDE="$SDK_BUNDLE/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/clang/include"
TOOLCHAIN_CLANG_INCLUDE="$TOOLCHAIN/usr/lib/swift/clang/include"

if [ -d "$SDK_BUNDLE" ] && [ -d "$TOOLCHAIN_CLANG_INCLUDE" ]; then
    if ! diff -rq "$SDK_CLANG_INCLUDE" "$TOOLCHAIN_CLANG_INCLUDE" >/dev/null 2>&1; then
        echo "→ Đồng bộ clang resource dir của SDK với toolchain…"
        rm -rf "$SDK_CLANG_INCLUDE"
        cp -r "$TOOLCHAIN_CLANG_INCLUDE" "$SDK_CLANG_INCLUDE"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Clean (tuỳ chọn). Bắt buộc sau khi di chuyển thư mục app: .build lưu
#    đường dẫn tuyệt đối.
# ---------------------------------------------------------------------------
if [ "$MODE" = "clean" ]; then
    echo "→ Xóa build cache…"
    rm -rf .build/out .build/checkouts .build/repositories \
           .build/workspace-state.json .build/build.db Package.resolved
fi

# ---------------------------------------------------------------------------
# 4. Version: tăng build number + ghi vào Info.plist
# ---------------------------------------------------------------------------
echo "→ Đánh version…"
"$TOOLKIT/bump_version.sh" "$APP_DIR"

# ---------------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------------
XTOOL="${XTOOL:-$TOOLKIT/xtool.AppImage}"
echo "→ Building với $XTOOL…"
"$XTOOL" dev build --ipa

IPA="$(ls -t xtool/*.ipa | head -1)"

# ---------------------------------------------------------------------------
# 6. Chèn app icon (SwiftPM không sinh icon — chèn thủ công vào IPA).
# ---------------------------------------------------------------------------
echo "→ Chèn app icon…"
"$TOOLKIT/patch_icon.sh" "$IPA" "${APP_ICON:-AppIcon.png}"

echo
echo "✅ Xong: $APP_DIR/$IPA"
ls -lh "$IPA"

# ---------------------------------------------------------------------------
# 7. Source SideStore chung + server LAN
# ---------------------------------------------------------------------------
echo
python3 "$TOOLKIT/sidestore_source.py"
"$TOOLKIT/serve_sidestore.sh"
