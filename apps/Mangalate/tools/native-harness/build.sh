#!/usr/bin/env bash
# Biên dịch phần phân tích pixel của appex (đúng file nguồn của app) thành CLI chạy trên Linux,
# dùng cho tools/e2e. Kết quả: <repo>/.state/mangalate/native-harness
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=../../.state/mangalate
mkdir -p "$OUT"
"${IOS_TOOLCHAIN:-$HOME/swift-dev}/usr/bin/swiftc" -O -swift-version 5 \
    Sources/MangalateExtension/PageAnalyzer.swift \
    Sources/MangalateExtension/PixelGrid.swift \
    tools/native-harness/main.swift \
    -o "$OUT/native-harness"
