#!/usr/bin/env bash
#
# Build Mangalate thành file .ipa (pipeline chung: ../../toolkit/build_app.sh).
#
#   ./build.sh          -> build (incremental)
#   ./build.sh clean    -> xóa build cache rồi build lại từ đầu
#
# Kết quả: ./xtool/Mangalate.ipa, source SideStore chung có Mangalate.
#
set -euo pipefail
cd "$(dirname "$0")"
exec ../../toolkit/build_app.sh . "$@"
