#!/usr/bin/env bash
#
# Phân loại game mới vào 3 nhóm trong ~/Documents/Game.
#
#   ./tools/phan_loai.sh          → xem game mới / cần đổi nhóm (an toàn)
#   ./tools/phan_loai.sh --apply  → di chuyển thật
#
# Thêm game mới: copy thư mục game vào ~/Documents/Game/ (gốc), rồi chạy lệnh này.
#
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/organize_games.py" "$@"
