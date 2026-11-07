#!/usr/bin/env bash
# libdobby.a và dobby.h ở thư mục này lấy từ release chính thức của
# jmpews/Dobby (dobby-iphoneos-all.tar.gz), slice arm64.
#
# Build lại từ mã nguồn (cần cmake + clang cross của toolchain đã dùng):
#   ./build.sh /đường/dẫn/Dobby-master
#
# Nếu CMake trên Linux không dựng được, giữ nguyên libdobby.a có sẵn
# (đã kiểm tra chứa _DobbyHook cho arm64).
set -euo pipefail

SRC="${1:?Cách dùng: build.sh <thư-mục-Dobby-master>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN="${IOS_TOOLCHAIN:-$HOME/swift-dev}"
SDK="${IOS_SDK:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
BUILD="$HERE/.build"

command -v cmake >/dev/null || { echo "❌ thiếu cmake (hoặc dùng pip install cmake)"; exit 1; }

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_C_COMPILER="$TOOLCHAIN/usr/bin/clang" \
  -DCMAKE_CXX_COMPILER="$TOOLCHAIN/usr/bin/clang++" \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DDOBBY_LIBRARY_TYPE=STATIC \
  -DDOBBY_BUILD_EXAMPLE=OFF -DDOBBY_BUILD_TEST=OFF

cmake --build "$BUILD" --target DobbyX -j
cp "$BUILD/libDobbyX.a" "$HERE/libdobby.a"
echo "→ đã cập nhật $HERE/libdobby.a"
