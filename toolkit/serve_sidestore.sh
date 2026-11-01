#!/usr/bin/env bash
#
# Server LAN cho iPhone (toolkit/dev_server.py): phục vụ sidestore/ để
# SideStore/AltStore tải bản build mới của mọi app + nhận clipboard từ nút
# "Gửi về máy tính" trong app (iPhone và máy tính phải cùng Wi-Fi).
#
#   toolkit/serve_sidestore.sh          -> chạy nền (bỏ qua nếu đang chạy)
#   toolkit/serve_sidestore.sh stop     -> dừng
#
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${SIDESTORE_PORT:-8765}"
PIDFILE=.state/sidestore_server.pid
LOG=.state/sidestore_server.log

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

if [ "${1:-}" = "stop" ]; then
    running && kill "$(cat "$PIDFILE")" && echo "Đã dừng server SideStore."
    rm -f "$PIDFILE"
    exit 0
fi

# Ghi lại source.json theo IP LAN hiện tại (đổi mạng thì IP đổi) và in URL để chép vào SideStore.
print_source() { python3 toolkit/sidestore_source.py | tail -1; }

if running; then
    echo "Server SideStore đang chạy (port $PORT)."
    print_source
    exit 0
fi

mkdir -p sidestore .state
nohup setsid python3 toolkit/dev_server.py "$PORT" >"$LOG" 2>&1 &
echo $! > "$PIDFILE"
echo "✅ Server SideStore chạy nền ở port $PORT (log: $LOG)"
print_source
