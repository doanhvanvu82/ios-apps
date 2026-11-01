#!/usr/bin/env bash
#
# Patch spine-unity.dll để Unity build không lỗi
# "Destroy may not be called from edit mode! Use DestroyImmediate instead."
#
#   ./patch_spine.sh <đường-dẫn-tới-spine-unity.dll>
#
# Hoặc dùng cho cả project:
#   ./patch_spine.sh --project <project-dir>     # patch mọi spine-unity.dll trong Assets/
#
# Cần Unity Editor (dùng MonoBleedingEdge + Mono.Cecil của Unity).
set -euo pipefail

UNITY_HOME="${UNITY_HOME:-$HOME/Unity}"
MONO_BIN="$UNITY_HOME/Editor/Data/MonoBleedingEdge/bin"
CECIL="$UNITY_HOME/Editor/Data/MonoBleedingEdge/lib/mono/gac/Mono.Cecil/0.11.1.0__0738eb9f132ed756/Mono.Cecil.dll"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patch_spine_editmode.cs"
EXE="${PATCH_EXE:-/tmp/patch_spine_editmode.exe}"

if [ ! -x "$MONO_BIN/mono" ] || [ ! -f "$CECIL" ]; then
    echo "❌ Không tìm thấy Unity Mono tại $MONO_BIN" >&2
    exit 1
fi

# Compile tool (bỏ qua nếu đã có)
if [ ! -f "$EXE" ] || [ "$SRC" -nt "$EXE" ]; then
    echo "→ Đang compile patch tool…"
    "$MONO_BIN/mcs" -target:exe -out:"$EXE" -r:"$CECIL" "$SRC" 2>&1 | grep -v "warning CS" || true
fi

patch_one() {
    local dll="$1"
    if [ ! -f "$dll" ]; then return 0; fi
    echo "→ Patch $dll"
    "$MONO_BIN/mono" "$EXE" "$dll"
}

if [ "${1:-}" = "--project" ]; then
    PROJECT="${2:?Usage: $0 --project <project-dir>}"
    while IFS= read -r dll; do
        patch_one "$dll"
    done < <(find "$PROJECT/Assets" -name "spine-unity.dll" 2>/dev/null)
else
    DLL="${1:?Usage: $0 <spine-unity.dll> | --project <project-dir>}"
    patch_one "$DLL"
fi
