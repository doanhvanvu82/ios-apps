#!/usr/bin/env bash
#
# Kích hoạt license Unity Personal (miễn phí) cho Unity Editor trên Linux.
#
#   ./unity_license.sh                 # kiểm tra trạng thái
#   ./unity_license.sh --activate      # kích hoạt (cần Unity ID)
#
# Unity Personal miễn phí, chỉ cần Unity ID (tài khoản miễn phí).
#
set -uo pipefail

UNITY_HOME="${UNITY_HOME:-$HOME/Unity}"
UNITY="$UNITY_HOME/Editor/Unity"
ULF="$HOME/.local/share/unity3d/Unity/Unity_lic.ulf"

if [ ! -x "$UNITY" ]; then
    echo "❌ Không tìm thấy Unity Editor tại $UNITY" >&2
    exit 1
fi

if [ "${1:-}" = "--activate" ]; then
    echo "→ Kích hoạt Unity Personal…"
    echo "   Sẽ mở trình duyệt để đăng nhập Unity ID."
    echo "   (Cần kết nối mạng)"
    echo
    "$UNITY" -batchmode -nographics -quit \
        -createManualActivationFile -logFile /tmp/unity-license.log 2>/dev/null || true

    # Unity hỗ trợ đăng nhập trực tiếp qua -username/-password (không khuyến nghị),
    # hoặc dùng file .alf upload lên license.unity3d.com.
    ALF=/tmp/Unity_v6000.alf
    if [ -f "$ALF" ]; then
        echo "→ Đã tạo file kích hoạt: $ALF"
        echo
        echo "   Upload file này lên: https://license.unity3d.com/manual"
        echo "   rồi tải .ulf về và copy vào: $ULF"
        echo
        echo "   Hoặc đăng nhập Unity Hub để kích hoạt tự động."
    else
        echo "→ Mở Unity Hub trên máy khác để activate, hoặc dùng license.unity3d.com/manual"
    fi
    exit 0
fi

# --- Kiểm tra trạng thái ---
if [ -f "$ULF" ]; then
    echo "✅ Đã có license: $ULF"
    grep -oE "<DeveloperData Value=\"[^\"]*\"" "$ULF" 2>/dev/null | head -2
else
    echo "❌ Chưa kích hoạt license."
    echo "   Chạy: $0 --activate"
fi

# Kiểm tra module WebGL
WEBGL_DIR="$UNITY_HOME/Editor/Data/PlaybackEngines/WebGLSupport"
if [ -d "$WEBGL_DIR" ]; then
    echo "✅ Module WebGL đã cài: $WEBGL_DIR"
else
    echo "❌ Thiếu module WebGL Build Support."
    echo "   Cài bằng Unity Hub hoặc giải nén UnitySetup-WebGL-*.tar.xz vào $UNITY_HOME/Editor/Data/PlaybackEngines/"
fi
