#!/usr/bin/env bash
#
# Build AdsBlocker thành file .ipa (pipeline chung: ../../toolkit/build_app.sh).
#
#   ./build.sh          -> build (incremental)
#   ./build.sh clean    -> xóa build cache rồi build lại từ đầu
#
# Kết quả: ./xtool/AdsBlocker.ipa, source SideStore chung có AdsBlocker.
# Mỗi lần build tải bộ lọc mới nhất (EasyList, ABPVN, EasyPrivacy) → WebExtension/filters/ (mất mạng thì dùng cache).
#
set -euo pipefail
cd "$(dirname "$0")"
node tools/build-filters.mjs
exec ../../toolkit/build_app.sh . "$@"
