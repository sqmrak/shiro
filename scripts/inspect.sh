#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tc="${SHIRO_TC:?set SHIRO_TC to the ios toolchain bin directory}"
for binary in build/ios/Shiro.app/Shiro build/ios/shirod build/ios/shirostatus.dylib build/ios/shirostatus-modern.dylib; do
    "$tc/lipo" -info "$binary"
    "$tc/otool" -L "$binary"
    "$tc/otool" -l "$binary" | sed -n '/LC_VERSION_MIN_IPHONEOS/,+4p; /LC_BUILD_VERSION/,+5p'
done
