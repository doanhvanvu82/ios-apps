#!/usr/bin/env bash
#
# Tiêm dylib mod (chặn quảng cáo + phát nền/PiP) vào IPA YouTube đã giải mã.
#
#   IPA=/đường/dẫn/YouTube.ipa ./build.sh
#   IPA_URL=https://… ./build.sh   # tải IPA về work/ nếu chưa có (dùng cho CI)
#   ./build.sh --check             # chỉ kiểm tra có IPA gốc không (exit 3 nếu thiếu)
#   SUFFIX= ./build.sh             # giữ bundle id gốc com.google.ios.youtube (MẶC ĐỊNH)
#   SUFFIX=mod ./build.sh          # đổi thành vn.vudv.youtube.mod, cài song song YouTube gốc
#
# Kết quả: out/YouTube_<tag>_<version>.ipa (+ .deb nếu có ldid/dpkg-deb)
#
# Giữ bundle id gốc là bắt buộc để đăng nhập Google: YouTube gửi bundle id lên
# máy chủ và Google từ chối "không thể xác nhận ứng dụng an toàn" với id lạ.
# App store / InnerTube cũng từ chối phục vụ trang chủ, video → màn hình skeleton.
#
# Dylib dùng method swizzling của ObjC runtime nên KHÔNG vá trang code của app;
# chỉ thêm LC_LOAD_DYLIB vào binary chính (LIEF), rồi ký ad-hoc toàn bộ bằng ldid.
# Không chạy được app trên Linux: kiểm chứng bằng cấu trúc IPA + log trên máy.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

WORK="$HERE/work"
OUT="$HERE/out"
APP_NAME="YouTube"
DYLIB_NAME="libyoutubemod.dylib"
MOD_VERSION="${MOD_VERSION:-3.14}"
# Nhãn build hiển thị trong menu (biết đang dùng bản mới hay cũ).
BUILD_LABEL="${BUILD_LABEL:-$(date +%y%m%d-%H%M)}"
# Mặc định giữ bundle id gốc: đổi id thì Google chặn đăng nhập và không trả
# dữ liệu trang chủ/video (xem đầu file).
if [ -z "${SUFFIX+x}" ]; then SUFFIX=""; fi

# Nguồn IPA: biến IPA > file mods/youtube/source.env (không commit) > IPA_URL.
if [ -z "${IPA:-}" ] && [ -f "$HERE/source.env" ]; then
  # shellcheck disable=SC1091
  . "$HERE/source.env"
fi

# --check: chỉ trả lời có IPA hay không (build_all.sh dùng để skip gọn).
if [ "${1:-}" = "--check" ]; then
  if [ -n "${IPA:-}" ] && [ -f "$IPA" ]; then exit 0; fi
  if [ -n "${IPA_URL:-}" ]; then exit 0; fi
  shopt -s nullglob
  for c in "$REPO"/*YouTube*.ipa "$REPO"/*youtube*.ipa "$HERE"/*.ipa; do
    [ -f "$c" ] && exit 0
  done
  exit 3
fi

if [ -z "${IPA:-}" ] && [ -n "${IPA_URL:-}" ]; then
  mkdir -p "$WORK"
  IPA="$WORK/source-$(basename "${IPA_URL%%\?*}")"
  if [ ! -f "$IPA" ]; then
    echo "→ tải IPA gốc từ IPA_URL…"
    curl -fL --retry 3 -o "$IPA.part" "$IPA_URL"
    mv "$IPA.part" "$IPA"
  fi
fi

if [ -z "${IPA:-}" ]; then
  shopt -s nullglob
  for candidate in "$REPO"/*YouTube*.ipa "$REPO"/*youtube*.ipa "$HERE"/*.ipa "$HOME/Downloads"/*YouTube*.ipa "$HOME/Downloads"/*youtube*.ipa; do
    if [ -f "$candidate" ]; then IPA="$candidate"; break; fi
  done
  shopt -u nullglob
fi
if [ -z "${IPA:-}" ]; then
  echo "❌ Chưa có IPA gốc: đặt IPA=/đường/dẫn/YouTube.ipa (hoặc IPA_URL=…, hoặc file mods/youtube/source.env)" >&2
  exit 1
fi

[ -f "$IPA" ] || { echo "❌ Không thấy IPA: $IPA" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Toolchain (Linux dùng Swift toolchain + Darwin SDK; macOS dùng Xcode có sẵn)
# ---------------------------------------------------------------------------
TOOLCHAIN="${IOS_TOOLCHAIN:-$HOME/swift-dev}"
SDK_DEFAULT="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
if [ "$(uname -s)" = "Darwin" ]; then
  CLANG="${IOS_CLANG:-$(xcrun -f clang)}"
  SDK="${IOS_SDK:-$(xcrun -sdk iphoneos --show-sdk-path)}"
  LD="${IOS_LD:-}"   # rỗng = ld của Apple
  OBJDUMP="${OBJDUMP:-$(xcrun -f llvm-objdump)}"
  NM="${NM:-$(xcrun -f llvm-nm)}"
else
  CLANG="${IOS_CLANG:-$TOOLCHAIN/usr/bin/clang}"
  SDK="${IOS_SDK:-$SDK_DEFAULT}"
  LD="${IOS_LD:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/toolset/bin/ld64.lld}"
  OBJDUMP="${OBJDUMP:-$TOOLCHAIN/usr/bin/llvm-objdump}"
  NM="${NM:-$TOOLCHAIN/usr/bin/llvm-nm}"
fi

[ -x "$CLANG" ] || { echo "❌ không thấy clang tại $CLANG" >&2; exit 1; }
[ -d "$SDK" ] || { echo "❌ không thấy iOS SDK tại $SDK" >&2; exit 1; }
if [ -n "$LD" ]; then
  [ -x "$LD" ] || { echo "❌ không thấy ld64.lld tại $LD" >&2; exit 1; }
fi

mkdir -p "$WORK" "$OUT" "$WORK/tools" "$WORK/obj" "$WORK/stage"

LDID="${LDID:-$WORK/tools/ldid}"
if [ ! -x "$LDID" ]; then
  echo "→ tải ldid…"
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) LDID_ASSET="ldid_linux_x86_64" ;;
    Linux-aarch64|Linux-arm64) LDID_ASSET="ldid_linux_aarch64" ;;
    Darwin-arm64) LDID_ASSET="ldid_macosx_arm64" ;;
    Darwin-x86_64) LDID_ASSET="ldid_macosx_x86_64" ;;
    *) echo "❌ kiến trúc lạ: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
  esac
  curl -fsSL -o "$LDID" "https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/$LDID_ASSET"
  chmod +x "$LDID"
fi

PY="python3"

echo "→ Toolchain: $("$CLANG" --version | head -1)"
echo "→ IPA: $IPA"

# ---------------------------------------------------------------------------
# 0. Giải nén IPA (1 lần; giải nén lại nếu IPA đổi)
# ---------------------------------------------------------------------------
IPA_STAMP="$WORK/orig/.ipa-source"
if [ ! -d "$WORK/orig/Payload" ] || [ "$(cat "$IPA_STAMP" 2>/dev/null)" != "$IPA" ]; then
  echo "→ giải nén IPA…"
  rm -rf "$WORK/orig"; mkdir -p "$WORK/orig"
  ( cd "$WORK/orig" && unzip -q -o "$IPA" )
  printf '%s' "$IPA" > "$IPA_STAMP"
fi
APP_SRC="$WORK/orig/Payload/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "❌ không thấy $APP_SRC trong IPA" >&2; exit 1; }
MAIN_BIN="$APP_SRC/$APP_NAME"
[ -f "$MAIN_BIN" ] || { echo "❌ không thấy binary $MAIN_BIN" >&2; exit 1; }

VERSION="$("$PY" - "$APP_SRC/Info.plist" <<'PY'
import plistlib,sys
print(plistlib.load(open(sys.argv[1],'rb'))["CFBundleShortVersionString"])
PY
)"
echo "→ Version IPA: $VERSION"

ENT_MAIN="$WORK/ent_main.plist"
if [ ! -s "$ENT_MAIN" ]; then
  "$LDID" -e "$MAIN_BIN" > "$ENT_MAIN" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 1. Build dylib
# ---------------------------------------------------------------------------
build_dylib() {
  local out="$1"
  local objdir="$WORK/obj/dylib"
  rm -rf "$objdir"; mkdir -p "$objdir"
  local objs=()
  for s in "$HERE/src/"*.mm; do
    local base; base="$(basename "$s" .mm)"
    local o="$objdir/$base.o"
    "$CLANG" -target arm64-apple-ios17.0 -isysroot "$SDK" \
      -fobjc-arc -O2 -fvisibility=hidden -Wno-deprecated-declarations \
      -DYT_VERSION_TAG="\"$MOD_VERSION\"" \
      -DYT_BUILD_LABEL="\"$BUILD_LABEL\"" \
      -I "$HERE/src" \
      -c "$s" -o "$o"
    objs+=("$o")
  done

  # -undefined dynamic_lookup: symbol của app dùng lúc chạy. Không dùng
  # -fvisibility=hidden cho hàm export (main.mm gọi XTDiagInstall…); hidden
  # + C++ name mangling từng làm dyld crash "symbol not found _YTDiagInstall".
  local link_args=()
  [ -n "$LD" ] && link_args+=("--ld-path=$LD")
  "$CLANG" -target arm64-apple-ios17.0 -isysroot "$SDK" ${link_args[@]+"${link_args[@]}"} \
    -dynamiclib -o "$out" "${objs[@]}" \
    -framework Foundation -framework UIKit -framework CoreFoundation \
    -install_name "@executable_path/Frameworks/$DYLIB_NAME" \
    -undefined dynamic_lookup \
    -Wl,-arch,arm64 -Wl,-platform_version,ios,17.0,17.0
  echo "→ dylib: $(du -h "$out" | cut -f1)  $out"
  # Tự kiểm tra: mọi hàm C dylib tự gọi (main.mm) phải định nghĩa trong dylib,
  # không được còn undefined — nếu không dyld abort lúc mở app.
  local undef
  undef=$("${NM:-$(command -v llvm-nm)}" -u "$out" 2>/dev/null \
    | grep -E '_(YTHooksInstall|YTMenuInstall|YTDiagInstall|YTModLogOpen|YTModBool|YTModLog)$' || true)
  if [ -n "$undef" ]; then
    echo "❌ dylib còn symbol nội bộ chưa định nghĩa:" >&2
    printf '   %s\n' $undef >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 2. Vá app: thêm LC_LOAD_DYLIB + Info.plist + ký ad-hoc
# ---------------------------------------------------------------------------
patch_app() {
  local app="$1" dylib="$2" bid="$3" disp="$4"
  local bin="$app/$APP_NAME"
  mkdir -p "$app/Frameworks"
  cp "$dylib" "$app/Frameworks/$DYLIB_NAME"

  echo "→ thêm LC_LOAD_DYLIB vào binary chính…"
  # Ghi vào padding header (không dựng lại LINKEDIT như LIEF) — xem tools/inject_dylib.py.
  python3 "$HERE/tools/inject_dylib.py" "$bin" "@executable_path/Frameworks/$DYLIB_NAME"

  # KHÔNG đổi CFBundleVersion/CFBundleShortVersionString: YouTube gửi chúng
  # làm clientVersion tới InnerTube, mà server chỉ chấp nhận version thật của
  # bản app (21.44.4). Version lạ → mọi API 404 → trang chủ/video skeleton.
  # Muốn cài đè bản mới thì gỡ app trong Ksign trước (không dựa episode).
  # Chỉ ghi đè bundle id khi SUFFIX khác rỗng — giữ id gốc thì Info.plist và
  # appex giữ nguyên id (điều kiện để Google cho đăng nhập và trả dữ liệu).
  "$PY" - "$app" "$bid" "$disp" "$SUFFIX" <<'PY'
import plistlib, sys, glob, os
app, bid, disp, suffix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = os.path.join(app, "Info.plist")
d = plistlib.load(open(p, 'rb'))
old_id = d.get("CFBundleIdentifier", "")
# Lấy log qua app Files khi cắm USB (toolkit/pull_app_logs.sh).
d["UIFileSharingEnabled"] = True
d["LSSupportsOpeningDocumentsInPlace"] = True
if suffix:
    d["CFBundleIdentifier"] = bid
    d["CFBundleDisplayName"] = disp
plistlib.dump(d, open(p, 'wb'), fmt=plistlib.FMT_BINARY)
print("→ Info.plist: id=%s name=%s version=%s build=%s" % (
    d["CFBundleIdentifier"], d.get("CFBundleDisplayName"),
    d.get("CFBundleShortVersionString"), d.get("CFBundleVersion")))

# App extension BẮT BUỘC có bundle id bắt đầu bằng bundle id app chính, nếu
# không installd từ chối cài: com.google.ios.youtube.ShareExtension → <bid>.ShareExtension.
if suffix:
    for ep in sorted(glob.glob(os.path.join(app, "PlugIns", "*.appex", "Info.plist"))):
        e = plistlib.load(open(ep, 'rb'))
        eid = e.get("CFBundleIdentifier", "")
        if eid.startswith(old_id + "."):
            tail = eid[len(old_id) + 1:]
        else:
            tail = eid.rsplit(".", 1)[-1]
        eid_new = "%s.%s" % (bid, tail)
        e["CFBundleIdentifier"] = eid_new
        plistlib.dump(e, open(ep, 'wb'), fmt=plistlib.FMT_BINARY)
        print("   appex: %s → %s" % (eid, eid_new))
PY

  # Bỏ MỌI chữ ký cũ (app chính, từng appex, framework). CodeResources cũ chứa
  # hash của bản Apple gốc — để lại thì iOS báo chữ ký tài nguyên không hợp lệ.
  find "$app" -name _CodeSignature -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$app" -name SC_Info -type d -prune -exec rm -rf {} + 2>/dev/null || true

  # Ký lại mọi Mach-O trong app (Ksign sẽ ký đè; ad-hoc để cấu trúc hợp lệ).
  if [ -s "$ENT_MAIN" ]; then
    "$LDID" -S"$ENT_MAIN" "$bin"
  else
    "$LDID" -S "$bin"
  fi
  "$LDID" -S "$app/Frameworks/$DYLIB_NAME"
  # Framework/extension đi kèm phải được ký lại vì binary chính đổi.
  find "$app/Frameworks" "$app/PlugIns" -type f 2>/dev/null | while IFS= read -r f; do
    [ "$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "cffaedfe" ] || continue
    case "$f" in
      "$app/Frameworks/$DYLIB_NAME") continue ;;
    esac
    "$LDID" -S "$f" 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# 3. Đóng gói + kiểm chứng
# ---------------------------------------------------------------------------
make_ipa() {
  local tag="$1" dylib="$2" bid="$3" disp="$4" outname="$5"
  local stage="$WORK/stage/$tag"
  echo "→ dựng ${stage}…"
  rm -rf "$stage"; mkdir -p "$stage"
  cp -a "$WORK/orig/Payload" "$stage/Payload"

  patch_app "$stage/Payload/$APP_NAME.app" "$dylib" "$bid" "$disp"

  local outp="$OUT/$outname"
  rm -f "$outp"
  ( cd "$stage" && zip -qry "$outp" Payload )
  echo "→ IPA: $(du -h "$outp" | cut -f1)  $outp"

  local app="$stage/Payload/$APP_NAME.app"
  echo "  • LC_LOAD_DYLIB:"
  "$OBJDUMP" --macho --dylibs-used "$app/$APP_NAME" | grep -c "$DYLIB_NAME" | sed 's/^/    count = /'
  echo "  • cf-bundle-id: $("$PY" - "$app/Info.plist" <<'PY'
import plistlib,sys
d=plistlib.load(open(sys.argv[1],'rb'))
print(d["CFBundleIdentifier"], "|", d.get("CFBundleDisplayName"))
PY
)"
  echo "  • cryptid (phải 0):"
  ("$OBJDUMP" --macho --private-headers "$app/$APP_NAME" 2>/dev/null | grep -A5 'LC_ENCRYPTION_INFO' | grep cryptid || echo "    (không đọc được)") | sed 's/^/    /'
  echo "  • extension ký lại: $(find "$app/PlugIns" -name '*.appex' 2>/dev/null | wc -l) appex"
  echo "  • số file trong IPA: $(unzip -l "$outp" | tail -1 | awk '{print $2}')"
  echo "  • kích thước dylib: $(du -h "$app/Frameworks/$DYLIB_NAME" | cut -f1)"
  rm -rf "$stage"
}

# ---------------------------------------------------------------------------
# 4. Chạy
# ---------------------------------------------------------------------------
if [ -z "$SUFFIX" ]; then
  BUNDLE_ID="com.google.ios.youtube"
  TAG="orig"
else
  BUNDLE_ID="vn.vudv.youtube.$SUFFIX"
  TAG="$SUFFIX"
fi

DYLIB="$WORK/build/$DYLIB_NAME"
mkdir -p "$WORK/build"
build_dylib "$DYLIB"

make_ipa "$TAG" "$DYLIB" "$BUNDLE_ID" "YouTube Mod" "${APP_NAME}_${TAG}_${VERSION}.ipa"

# .deb (cho máy jailbreak) — chỉ khi có ldid/dpkg-deb.
if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_ROOT="$WORK/deb"
  rm -rf "$DEB_ROOT"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries"
  cp "$DYLIB" "$DEB_ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries/$DYLIB_NAME"
  cat > "$DEB_ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries/YouTubeMod.plist" <<'PLIST'
{
    Filter = { Bundles = ( "com.google.ios.youtube" ); };
}
PLIST
  cat > "$DEB_ROOT/DEBIAN/control" <<CONTROL
Package: vn.vudv.youtube.mod
Name: YouTube Mod
Version: ${MOD_VERSION}
Architecture: iphoneos-arm64
Description: Chặn quảng cáo và mở phát nền/PiP cho YouTube (21.44.4).
Maintainer: vudv
Section: Tweaks
Depends: mobilesubstrate
CONTROL
  dpkg-deb -Zgzip -b "$DEB_ROOT" "$OUT/YouTubeMod_${MOD_VERSION}.deb" >/dev/null
  echo "→ deb: $OUT/YouTubeMod_${MOD_VERSION}.deb"
fi

echo
echo "✔ Xong. out/ có:"
ls -la "$OUT"
