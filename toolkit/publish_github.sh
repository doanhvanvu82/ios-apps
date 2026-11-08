#!/usr/bin/env bash
#
# Đẩy bản build mới nhất của mọi app lên GitHub Releases và cập nhật
# source/source.json — để Ksign (đọc source AltStore) dùng một URL CỐ ĐỊNH
# (raw.githubusercontent.com) thay vì IP LAN đổi theo mạng.
#
#   toolkit/publish_github.sh             -> sinh source + commit/push + upload release
#   toolkit/publish_github.sh --dry-run   -> chỉ sinh .state/publish/source.json, không đụng GitHub
#
#   PUBLISH_ONLY=Mangalate toolkit/publish_github.sh   -> chỉ publish mục vừa build;
#     giữ nguyên app khác trong source.json + asset cũ trên release (publish thường
#     build lại tất cả nên không cần). CI đặt PUBLISH_ONLY khi workflow chạy scope/only.
#
# Biến môi trường: GH_OWNER, GH_REPO, GH_TAG (mặc định doanhvanvu82/ios-apps/builds).
# Token: $GH_TOKEN, không có thì đọc mục github.com trong ~/.git-credentials.
#
# Cấu trúc URL sau khi publish:
#   source.json  https://raw.githubusercontent.com/<owner>/<repo>/main/source/source.json
#   IPA / icon   https://github.com/<owner>/<repo>/releases/download/<tag>/<file>
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OWNER="${GH_OWNER:-doanhvanvu82}"
REPO="${GH_REPO:-ios-apps}"
TAG="${GH_TAG:-builds}"
MODE="${1:-}"

BASE="https://github.com/$OWNER/$REPO/releases/download/$TAG"
SOURCE_URL="https://raw.githubusercontent.com/$OWNER/$REPO/main/source/source.json"
OUT_DIR=.state/publish
PUBLISH_ONLY="${PUBLISH_ONLY:-}"
# Publish từng phần: giữ app khác trong source.json + asset cũ trên release.
PARTIAL=0
[ -n "$PUBLISH_ONLY" ] && PARTIAL=1

# ---------------------------------------------------------------------------
# 1. Sinh source.json trỏ tới GitHub Releases (IPA/icon copy sang .state/publish,
#    không nằm trong repo).
# ---------------------------------------------------------------------------
echo "→ Sinh source.json (base: $BASE)…"
rm -rf "$OUT_DIR"
DIST_ARGS=()
if [ -n "${DIST_DIR:-}" ]; then
    DIST_ARGS=(--dist "$DIST_DIR")
fi
MERGE_ARGS=()
if [ "$PARTIAL" = "1" ]; then
    mkdir -p "$OUT_DIR"
    if SRC_URL="$SOURCE_URL" python3 - "$OUT_DIR/source.prev.json" <<'PY'
import os, sys, urllib.request
url = os.environ.get("SRC_URL", "")
try:
    with urllib.request.urlopen(url, timeout=20) as r:
        open(sys.argv[1], "wb").write(r.read())
except Exception as exc:
    print(f"⚠️ không tải được source.json cũ ({exc}); chỉ publish mục vừa build.")
PY
    then
        MERGE_ARGS=(--merge-from "$OUT_DIR/source.prev.json")
    fi
fi
SOURCE_NAME="iOS apps" SOURCE_OUT="$OUT_DIR" python3 toolkit/sidestore_source.py "$BASE" --source-url "$SOURCE_URL" \
    "${DIST_ARGS[@]+"${DIST_ARGS[@]}"}" "${MERGE_ARGS[@]+"${MERGE_ARGS[@]}"}"

# Không bao giờ push source.json rỗng (vd artifact CI giải nén sai thư mục):
# Ksign sẽ mất toàn bộ app.
COUNT="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['apps']))" "$OUT_DIR/source.json")"
if [ "$COUNT" -eq 0 ]; then
    echo "❌ source.json không có app nào — kiểm tra IPA trong ${DIST_DIR:-apps+mods}." >&2
    exit 1
fi

echo "→ Source có $COUNT mục."

mkdir -p source
cp "$OUT_DIR/source.json" source/source.json

if [ "$MODE" = "--dry-run" ]; then
    echo "→ Dry run: xem $OUT_DIR/source.json (chưa đụng GitHub)."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Token (gh không đăng nhập sẵn trên máy này)
# ---------------------------------------------------------------------------
if [ -z "${GH_TOKEN:-}" ] && [ -f "$HOME/.git-credentials" ]; then
    GH_TOKEN="$(grep -m1 '@github.com' "$HOME/.git-credentials" \
        | sed -E 's#https://[^:]+:([^@]+)@github.com#\1#')" || true
fi
[ -n "${GH_TOKEN:-}" ] || { echo "❌ Thiếu GH_TOKEN (hoặc mục github.com trong ~/.git-credentials)." >&2; exit 1; }
export GH_TOKEN

# ---------------------------------------------------------------------------
# 3. Repo + commit source.json
# ---------------------------------------------------------------------------
if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
    echo "→ Tạo repo $OWNER/$REPO (public)…"
    gh repo create "$OWNER/$REPO" --public \
        --description "App iOS build bằng xtool trên Linux, phân phối qua Ksign"
fi

[ -d .git ] || git init -q -b main
git remote get-url origin >/dev/null 2>&1 \
    || git remote add origin "https://github.com/$OWNER/$REPO.git"

git add source/source.json
if ! git diff --cached --quiet; then
    git commit -q -m "build: cập nhật source.json $(date -u +%Y-%m-%dT%H:%MZ)"
fi
git push -q -u origin main
echo "→ Đã push source.json."

# ---------------------------------------------------------------------------
# 4. Release: upload IPA/icon mới, xoá asset của bản cũ (giữ release nhỏ)
# ---------------------------------------------------------------------------
if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "Bản build mới nhất" --latest \
        --notes "IPA mới nhất của mọi app. Source Ksign: $SOURCE_URL"
fi

shopt -s nullglob
FILES=("$OUT_DIR"/*.ipa "$OUT_DIR"/*.png)
[ ${#FILES[@]} -gt 0 ] || { echo "❌ Không có IPA nào để upload (build app trước)." >&2; exit 1; }
gh release upload "$TAG" "${FILES[@]}" --clobber
echo "→ Đã upload ${#FILES[@]} file lên release '$TAG'."

if [ "$PARTIAL" = "1" ]; then
    # Chỉ dọn asset của đúng những app vừa build (tên từ .built-apps.json), để
    # mapping cũ ↔ mới chính xác kể cả khi hai app trùng tên file.
    BUILD_LIST="$OUT_DIR/.built-apps.json" OUT="$OUT_DIR" TAG="$TAG" python3 <<'PY'
import json, os, subprocess
built = json.load(open(os.environ["BUILD_LIST"]))
keep = set(os.listdir(os.environ["OUT"]))
stems = sorted({a["name"].replace(" ", "") for a in built})
tag = os.environ["TAG"]
assets = json.loads(subprocess.run(
    ["gh", "release", "view", tag, "--json", "assets"],
    capture_output=True, text=True, check=True).stdout)["assets"]
for asset in assets:
    n = asset["name"]
    if n in keep:
        continue
    if any(n.startswith(s + "-") or n == s + ".png" or n == s + ".ipa" for s in stems):
        subprocess.run(["gh", "release", "delete-asset", tag, n, "-y"],
                       capture_output=True)
        print(f"   xoá asset cũ: {n}")
PY
else
    KEEP="$(cd "$OUT_DIR" && ls)"
    while read -r asset; do
        [ -n "$asset" ] || continue
        if ! printf '%s\n' "$KEEP" | grep -qx "$asset"; then
            gh release delete-asset "$TAG" "$asset" -y >/dev/null 2>&1 || true
            echo "   xoá asset cũ: $asset"
        fi
    done < <(gh release view "$TAG" --json assets -q '.assets[].name')
fi

echo
echo "✅ Source cố định cho Ksign:"
echo "   $SOURCE_URL"
echo "   (IPA tải từ $BASE/<App>-<version>.ipa)"
