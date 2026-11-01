#!/usr/bin/env bash
#
# Tải Unity Editor (version cụ thể) + module WebGL cho Linux.
#
#   ./unity_fetch_version.sh 2021.3.42f1 [2021.3.42f1 ...]
#
# Cài vào ~/unity-versions/<version>/  (mỗi version một thư mục riêng).
#
set -euo pipefail

VERSIONS_DIR="${UNITY_VERSIONS:-$HOME/unity-versions}"
DL_DIR="${UNITY_DL_DIR:-$HOME/unity-dl/versions}"
mkdir -p "$VERSIONS_DIR" "$DL_DIR"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <version> [version...]" >&2
    exit 1
fi

for VER in "$@"; do
    TARGET="$VERSIONS_DIR/$VER"
    # Đã cài đủ editor + module WebGL → bỏ qua.
    if [ -x "$TARGET/Editor/Unity" ] && [ -d "$TARGET/Editor/Data/PlaybackEngines/WebGLSupport" ]; then
        echo "⏭  $VER — đã cài (kèm WebGL)"
        continue
    fi

    echo "→ Lấy thông tin Unity $VER…"
    META="$(curl -s --max-time 30 \
        "https://services.api.unity.com/unity/editor/release/v1/releases?version=$VER&limit=1")"

    EDITOR_URL="$(echo "$META" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rs=d.get('results',[])
if not rs: sys.exit(1)
for dl in rs[0].get('downloads',[]):
    if dl.get('platform')=='LINUX' and dl.get('type') in ('TAR_XZ','TAR_GZ','EDITOR'):
        print(dl['url']); break
")" || { echo "❌ Không tìm thấy bản Linux cho $VER"; continue; }

    WEBGL_URL="$(echo "$META" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for dl in d.get('results',[])[0].get('downloads',[]):
    if dl.get('platform')!='LINUX': continue
    for m in dl.get('modules',[]):
        if m.get('id')=='webgl':
            print(m['url']); sys.exit()
")" || WEBGL_URL=""

    echo "   Editor: $EDITOR_URL"
    [ -n "$WEBGL_URL" ] && echo "   WebGL : $WEBGL_URL"

    mkdir -p "$TARGET"
    echo "→ Tải editor (~3 GB)…"
    if [ ! -f "$DL_DIR/editor-$VER.tar.xz" ] || [ ! -s "$DL_DIR/editor-$VER.tar.xz" ]; then
        curl -fL --retry 3 -o "$DL_DIR/editor-$VER.tar.xz" "$EDITOR_URL"
    else
        echo "   (dùng lại tarball đã tải)"
    fi

    echo "→ Giải nén editor…"
    # Tarball có sẵn thư mục "Editor/" ở gốc → giải nén nguyên vẹn vào $TARGET.
    rm -rf "$TARGET" && mkdir -p "$TARGET"
    tar xJf "$DL_DIR/editor-$VER.tar.xz" -C "$TARGET"

    if [ -n "$WEBGL_URL" ]; then
        echo "→ Tải module WebGL…"
        curl -fL --retry 3 -o "$DL_DIR/webgl-$VER.tar.xz" "$WEBGL_URL"
        echo "→ Giải nén WebGL…"
        # Module có "Editor/Data/PlaybackEngines/WebGLSupport/…" → giải nén vào $TARGET.
        tar xJf "$DL_DIR/webgl-$VER.tar.xz" -C "$TARGET"
    fi

    "$TARGET/Editor/Unity" -version 2>&1 | head -1
    echo "✅ Unity $VER đã cài tại $TARGET"
    echo
done
