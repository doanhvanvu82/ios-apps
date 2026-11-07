#!/usr/bin/env bash
#
# Pipeline tiêm dylib mod menu vào Cherry Tale IPA.
#
#   PHASE=recon ./build.sh     # chỉ resolve + ghi log, không hook (mặc định)
#   PHASE=full  ./build.sh     # menu + hook
#   SUFFIX= ./build.sh         # giữ nguyên bundle id gốc (mặc định: mod)
#   SUFFIX=abc ./build.sh      # bundle id vn.vudv.cherrytale.abc
#
# Mỗi lần luôn sinh 2 IPA: bản thường và bản _safe (không cài hook nào).
# Kết quả: out/CherryTale_<tag>_<version>.ipa (+ _safe), out/report.md
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
IPA="${IPA:-$REPO/0929_30_1_CherryTale.ipa}"
WORK="$HERE/work"
OUT="$HERE/out"
PHASE="${PHASE:-recon}"

# Mặc định SUFFIX=mod -> vn.vudv.cherrytale.mod. SUFFIX= (rỗng) -> giữ id gốc.
if [ -z "${SUFFIX+x}" ]; then SUFFIX="mod"; fi

ORIG_ID="com.neversoft.rpg.erolabsios2"

case "$PHASE" in
  recon|full) ;;
  *) echo "❌ PHASE phải là recon hoặc full (đang: $PHASE)" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
TOOLCHAIN="${IOS_TOOLCHAIN:-$HOME/swift-dev}"
CLANG="$TOOLCHAIN/usr/bin/clang"
OBJDUMP="$TOOLCHAIN/usr/bin/llvm-objdump"
SDK="${IOS_SDK:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
LD="${IOS_LD:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/toolset/bin/ld64.lld}"

[ -x "$CLANG" ] || { echo "❌ không thấy clang tại $CLANG" >&2; exit 1; }
[ -d "$SDK" ] || { echo "❌ không thấy iOS SDK tại $SDK" >&2; exit 1; }
[ -x "$LD" ] || { echo "❌ không thấy ld64.lld tại $LD" >&2; exit 1; }

mkdir -p "$WORK" "$OUT" "$WORK/tools" "$WORK/obj" "$WORK/stage"

# ldid: dùng bản tải sẵn, thiếu thì tải
LDID="${LDID:-$WORK/tools/ldid}"
if [ ! -x "$LDID" ]; then
  echo "→ tải ldid…"
  curl -sL -o "$LDID" https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64
  chmod +x "$LDID"
fi

# venv cho LIEF (vá Mach-O)
if [ ! -x "$WORK/venv/bin/python" ]; then
  echo "→ tạo venv + cài LIEF…"
  python3 -m venv "$WORK/venv"
  "$WORK/venv/bin/pip" install -q lief
fi
PY="$WORK/venv/bin/python"

echo "→ Toolchain: $("$CLANG" --version | head -1)"
echo "→ SDK: $SDK"
echo "→ Phase: $PHASE   SUFFIX: '${SUFFIX}'"

# ---------------------------------------------------------------------------
# 0. Giải nén IPA gốc (1 lần)
# ---------------------------------------------------------------------------
if [ ! -d "$WORK/orig/Payload" ]; then
  echo "→ giải nén IPA…"
  rm -rf "$WORK/orig"; mkdir -p "$WORK/orig"
  ( cd "$WORK/orig" && unzip -q -o "$IPA" )
fi
APP_SRC="$WORK/orig/Payload/CherryTale.app"
UF="$APP_SRC/Frameworks/UnityFramework.framework/UnityFramework"
[ -f "$UF" ] || { echo "❌ không thấy UnityFramework" >&2; exit 1; }

VERSION="$("$PY" - "$APP_SRC/Info.plist" <<'PY'
import plistlib,sys
print(plistlib.load(open(sys.argv[1],'rb'))["CFBundleShortVersionString"])
PY
)"
echo "→ Version IPA: $VERSION"

# entitlements gốc của binary chính (giữ nguyên khi ký lại)
ENT_MAIN="$WORK/ent_main.plist"
if [ ! -s "$ENT_MAIN" ]; then
  "$LDID" -e "$APP_SRC/CherryTale" > "$ENT_MAIN" 2>/dev/null || true
fi

# Sinh hook tĩnh (trampoline + slot) từ dump.cs — cần capstone.
GEN="$WORK/gen"
if [ ! -f "$GEN/ct_targets.h" ] || [ "$WORK/dump/dump.cs" -nt "$GEN/ct_targets.h" ]    || [ "$HERE/tools/make_static_hooks.py" -nt "$GEN/ct_targets.h" ]; then
  echo "→ sinh hook tĩnh từ dump.cs…"
  mkdir -p "$GEN"
  CT_WITH_CLICK=1 "$PY" "$HERE/tools/make_static_hooks.py" generate "$UF" "$WORK/dump/dump.cs" "$GEN"
fi

# dump.cs.gz (tuỳ chọn, cho nút "Xuất dump.cs")
if [ "$PHASE" = "full" ] && [ -f "$WORK/dump/dump.cs" ] && [ ! -f "$WORK/dump.cs.gz" ]; then
  gzip -9 -c "$WORK/dump/dump.cs" > "$WORK/dump.cs.gz"
fi

# ---------------------------------------------------------------------------
# 1. Build dylib
#    $1 = safe (0/1), $2 = đường dẫn ra
# ---------------------------------------------------------------------------
build_dylib() {
  local safe="$1" out="$2"
  local objdir="$WORK/obj/$(basename "$out" .dylib)"
  rm -rf "$objdir"; mkdir -p "$objdir"
  local recon=0; [ "$PHASE" = "recon" ] && recon=1
  local srcs=("$HERE/src/"*.mm "$HERE/src/ui/"*.mm)
  local asm="$WORK/gen/ct_tramps.s"
  echo "→ biên dịch dylib ($(basename "$out"), recon=$recon safe=$safe)…"

  local objs=()
  for s in "${srcs[@]}"; do
    local base; base="$(basename "$s" .mm)"
    local o="$objdir/$base.o"
    "$CLANG" -target arm64-apple-ios15.0 -isysroot "$SDK" \
      -fobjc-arc -O2 -fvisibility=hidden -Wno-deprecated-declarations \
      -DCT_RECON_PHASE=$recon -DCT_SAFE_BUILD=$safe \
      -I "$HERE/src" -I "$WORK/gen" \
      -c "$s" -o "$o"
    objs+=("$o")
  done

  "$CLANG" -target arm64-apple-ios15.0 -isysroot "$SDK" -c "$asm" -o "$objdir/ct_tramps.o"
  objs+=("$objdir/ct_tramps.o")

  "$CLANG" -target arm64-apple-ios15.0 -isysroot "$SDK" --ld-path="$LD" \
    -dynamiclib -o "$out" "${objs[@]}" \
    -framework Foundation -framework UIKit -lz -lc++ \
    -install_name @rpath/libcherrytale.dylib \
    -undefined dynamic_lookup \
    -Wl,-arch,arm64 -Wl,-platform_version,ios,15.0,15.0
  echo "→ dylib: $(du -h "$out" | cut -f1)  $out"
}

# ---------------------------------------------------------------------------
# 2. Vá app + ký ad-hoc
#    $1 = thư mục .app, $2 = dylib, $3 = bundle id, $4 = display name
# ---------------------------------------------------------------------------
patch_app() {
  local app="$1" dylib="$2" bid="$3" disp="$4"
  cp "$dylib" "$app/Frameworks/libcherrytale.dylib"

  echo "→ vá tĩnh hook vào UnityFramework…"
  "$PY" "$HERE/tools/make_static_hooks.py" patch "$app/Frameworks/UnityFramework.framework/UnityFramework" "$WORK/gen"

  "$PY" - "$app/Frameworks/UnityFramework.framework/UnityFramework" <<'PY'
import sys, lief
p = sys.argv[1]
b = lief.MachO.parse(p).at(0)
want = "@executable_path/Frameworks/libcherrytale.dylib"
have = [c.name for c in b.libraries]
if want not in have:
    b.add_library(want)
    b.write(p)
    print("→ đã thêm LC_LOAD_DYLIB", want)
else:
    print("→ LC_LOAD_DYLIB đã có, bỏ qua")
PY

  "$PY" - "$app/Info.plist" "$bid" "$disp" <<'PY'
import plistlib, sys
p, bid, disp = sys.argv[1], sys.argv[2], sys.argv[3]
d = plistlib.load(open(p, 'rb'))
d["CFBundleIdentifier"] = bid
d["CFBundleDisplayName"] = disp
# cho phép lấy file recon qua app Files
d["UIFileSharingEnabled"] = True
d["LSSupportsOpeningDocumentsInPlace"] = True
plistlib.dump(d, open(p, 'wb'), fmt=plistlib.FMT_BINARY)
print("→ Info.plist: id=%s name=%s" % (bid, disp))
PY

  # bỏ chữ ký cũ (Ksign sẽ ký lại; ad-hoc chỉ để cấu trúc hợp lệ)
  rm -rf "$app/_CodeSignature" "$app/Frameworks/UnityFramework.framework/_CodeSignature"

  if [ -s "$ENT_MAIN" ]; then
    "$LDID" -S"$ENT_MAIN" "$app/CherryTale"
  else
    "$LDID" -S "$app/CherryTale"
  fi
  "$LDID" -S "$app/Frameworks/UnityFramework.framework/UnityFramework"
  "$LDID" -S "$app/Frameworks/libcherrytale.dylib"
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

  patch_app "$stage/Payload/CherryTale.app" "$dylib" "$bid" "$disp"

  # dump.cs.gz (nếu có)
  if [ -f "$WORK/dump.cs.gz" ]; then
    cp "$WORK/dump.cs.gz" "$stage/Payload/CherryTale.app/dump.cs.gz"
  fi

  local outp="$OUT/$outname"
  rm -f "$outp"
  ( cd "$stage" && zip -qry "$outp" Payload )
  echo "→ IPA: $(du -h "$outp" | cut -f1)  $outp"

  # --- kiểm chứng cấu trúc ---
  local uf="$stage/Payload/CherryTale.app/Frameworks/UnityFramework.framework/UnityFramework"
  echo "  • dylibs-used:"; "$OBJDUMP" --macho --dylibs-used "$uf" | grep -c 'libcherrytale' | sed 's/^/    libcherrytale count = /'
  echo "  • cf-bundle-id: $("$PY" - "$stage/Payload/CherryTale.app/Info.plist" <<'PY'
import plistlib,sys
d=plistlib.load(open(sys.argv[1],'rb'))
print(d["CFBundleIdentifier"], "|", d.get("CFBundleDisplayName"))
PY
)"
  echo "  • entitlements sau ký:"; "$LDID" -e "$stage/Payload/CherryTale.app/CherryTale" | grep -E 'application-identifier|team-identifier' | sed 's/^/    /'
  echo "  • số file trong IPA: $(unzip -l "$outp" | tail -1 | awk '{print $2}')"
  rm -rf "$stage"
}

# ---------------------------------------------------------------------------
# 4. Chạy 2 biến thể
# ---------------------------------------------------------------------------
if [ -z "$SUFFIX" ]; then
  ID_NORMAL="$ORIG_ID"
  ID_SAFE="${ORIG_ID}.safe"
  TAG="orig"
else
  ID_NORMAL="vn.vudv.cherrytale.$SUFFIX"
  ID_SAFE="vn.vudv.cherrytale.${SUFFIX}safe"
  TAG="$SUFFIX"
fi

DYLIB_NORMAL="$WORK/build/libcherrytale_${TAG}.dylib"
DYLIB_SAFE="$WORK/build/libcherrytale_${TAG}_safe.dylib"

build_dylib 0 "$DYLIB_NORMAL"
build_dylib 1 "$DYLIB_SAFE"

make_ipa "$TAG"       "$DYLIB_NORMAL" "$ID_NORMAL" "Cherry Tale Mod"        "CherryTale_${TAG}_${VERSION}.ipa"
make_ipa "${TAG}_safe" "$DYLIB_SAFE"  "$ID_SAFE"   "Cherry Tale Mod (Safe)" "CherryTale_${TAG}_${VERSION}_safe.ipa"

# ---------------------------------------------------------------------------
# 5. Báo cáo
# ---------------------------------------------------------------------------
"$PY" - "$OUT/report.md" "$VERSION" "$PHASE" "$TAG" "$ID_NORMAL" "$ID_SAFE" "$ORIG_ID" <<'PY'
import sys, datetime
path, ver, phase, tag, idn, ids, orig = sys.argv[1:8]
body = f"""# Cherry Tale Mod — báo cáo build

- Ngày build: {datetime.datetime.now().isoformat(timespec='seconds')}
- IPA gốc: `0929_30_1_CherryTale.ipa`
- Version game: **{ver}** (build 595, IPA ngày 2026-09-29)
- Phase: **{phase}**
- Bundle id gốc: `{orig}`
- Bundle id bản thường: `{idn}`
- Bundle id bản _safe: `{ids}`

## Version

- IPA này: **{ver}** (build 595, đóng gói 2026-09-29).
- Bản live: **chưa kiểm chứng được** từ môi trường build (không truy cập store của EroLabs). Nếu live đang là 2.2.x thì metadata/il2cpp có thể lệch giữa các bản vá; luôn mod đúng file IPA đã dump.

## Đã kiểm tra ở bước 0

- `LC_ENCRYPTION_INFO_64.cryptid = 0` trên `CherryTale` và `UnityFramework` → IPA đã giải mã, không còn FairPlay.
- `Data/Managed/Metadata/global-metadata.dat` magic `AF 1B B1 FA` → metadata không bị obfuscate.
- Cả hai binary là **arm64** (không phải arm64e) → hook trực tiếp, không cần ptrauth.
- il2cpp nằm trong `Frameworks/UnityFramework.framework/UnityFramework` (232 symbol `il2cpp_*` export), không phải binary chính.
- URL scheme khai báo: `com.superhgame.emma`, `erolabsfe8603fd` — không trùng bundle id mới, không xung đột.

## Cấu trúc mod

- Dylib: `libcherrytale.dylib` (arm64, ObjC++ + UIKit, không Swift).
- Tiêm bằng `LC_LOAD_DYLIB @executable_path/Frameworks/libcherrytale.dylib` vào UnityFramework.
- Resolve class/method theo **tên** qua il2cpp API lúc runtime, có retry (~90 s), không hard-code RVA.
- **Hook tĩnh**: `tools/make_static_hooks.py` vá 17 entry hàm trong UnityFramework lúc build (stub `adrp/ldr/br` qua slot ở segment `__CTHOOK`), rồi Ksign ký lại toàn bộ. Không sửa trang code lúc chạy nên không vi phạm `CS_HARD|CS_KILL`.
- Lý do không dùng Dobby: bản ký của Ksign không có `get-task-allow`/`CS_DEBUGGED`; mọi thao tác làm trang `__TEXT` thành writable đều khiến kernel giết (`CODESIGNING / Invalid Page`). Dylib chỉ ghi vào slot (trang dữ liệu).
- Cấu hình lưu ở NSUserDefaults suite `vn.vudv.cherrytale.mod`.

## Danh sách hook (phase full)

| Tab | Mục | Rủi ro | Hook |
|-----|-----|--------|------|
| Chiến đấu | Sát thương gây x | vừa | `NumericSkillManager.GetBaseDmgWith_CritAndBlk` |
| Chiến đấu | Giảm sát thương nhận x | vừa | cùng hook trên |
| Chiến đấu | Bất tử | vừa | `NumericSkillManager.CheckDmgIsInvalid` |
| Chiến đấu | Luôn chí mạng | vừa | `NumericSkillManager.IsCritial` |
| Chiến đấu | Hệ số chí mạng | vừa | cùng hook sát thương (nhân thêm khi cờ crit) |
| Chiến đấu | Hồi chiêu = 0 | vừa | `NumericActor.GetSkillCDTime` |
| Chiến đấu | Điểm kỹ năng vô hạn | vừa | `NumericBattleCenter.GetMana` |
| Chiến đấu | Tốc độ trận | vừa | `UnityEngine.Time.set_timeScale` |
| Chiến đấu | Tự thắng trận | **cao** | `NumericCalculate.IsWin` |
| Chiến đấu | Quái HP = 1 | **cao** | `BattleFormula.Get_Final_HP` |
| Gallery | Mở khoá Puzzles | an toàn | `RolePuzzleData.get_GetOpenLv`, `RoleSecretSetionData.get_GetOpenLv` |
| Gallery | Peachy Secrets | an toàn | `RoleSecret.IsLock` |
| Gallery | Instant Climax | an toàn | `SecretHCGClickGameMainUI.AddExcited` |
| Gallery | Affection tối đa | an toàn | `RoleFavorability.get_Exp`, `get_Level` |
| Gallery | Mở khoá CG/truyện | an toàn | `RoleSecret.IsLock` |
| QoL | Bỏ animation trận | vừa | `BattleCenter.IsSkipBattle` |
| QoL | Tự lặp ải | vừa | `StageModule.get_IsNeedAutoFight`, `UIPreferecneModule.get_AutoFighting` |
| QoL | Bỏ qua tutorial | vừa | `TeachingModule.isTeachingID_CanBeTrigger` |

Tên thực tế resolve được ghi trong `Documents/cherrytale_recon.txt` trên máy (bản recon) và trong log panel (bản full).

## Cách đổi giá trị mặc định

Sửa `CTFeatureDef` trong `src/hooks.mm` (trường `defaultValue`), hoặc đổi `g_dmgMul = 3.0f` v.v. ở đầu file. Giá trị đã lưu trong NSUserDefaults sẽ đè lên mặc định.

## Cách gỡ nếu crash

1. Cài bản **`_safe`** (cùng file IPA, hậu tố `_safe`): không cài hook nào, chỉ menu + recon.
2. Hoặc trong menu → tab **Debug** → **TẮT TOÀN BỘ (khẩn cấp)**: tắt cờ hành vi ngay và ghi `emergency_disabled = YES` để lần khởi động sau không cài hook.
3. Gỡ hẳn: xoá app, cài lại IPA gốc.

## Rủi ro

- Toàn bộ thay đổi là **client-side**. Không đổi kim cương, không đổi roster.
- Game có `NumericCalculate.OnVerifyClientDamage` và `NumcVerifyProofs` → server đối chiếu sát thương. Sửa sát thương có thể bị lệch verify/bị đánh dấu. Rủi ro ban là **có**.
- `Tự thắng trận` và `Quái HP = 1` chạm vào kết quả mô phỏng → rủi ro cao nhất, nên tránh ở tài khoản chính.
- Bản mod đổi bundle id → **mất keychain cũ**, phải đăng nhập lại. Dùng **tài khoản rác** cho bản mod.
- iOS 27 sideload: chọn file ngoài container hay lỗi (đã ghi trong AGENTS.md); lấy log bằng app Files với `UIFileSharingEnabled` đã bật.

## File

- `out/CherryTale_{tag}_{ver}.ipa` — bản thường
- `out/CherryTale_{tag}_{ver}_safe.ipa` — bản cứu hộ (không hook)
- `out/report.md` — file này
"""
open(path, 'w', encoding='utf-8').write(body)
print("→ report:", path)
PY

echo "✔ Xong. out/ có:"
ls -la "$OUT"
