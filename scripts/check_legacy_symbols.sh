#!/usr/bin/env bash
# every symbol the armv7 slice imports must exist in the iOS 5 runtime, or dyld refuses to launch it
set -euo pipefail

BIN="${1:?usage: check_legacy_symbols.sh <fat executable>}"
TC="${SHIRO_TC:?set SHIRO_TC to the ios toolchain bin directory}"
SDK5="${SHIRO_SDK_V5:?set SHIRO_SDK_V5 to an iphoneos 5.x sdk}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

"${TC}/lipo" -thin armv7 "${BIN}" -output "${WORK}/armv7"
"${TC}/nm" -u "${WORK}/armv7" | awk '{print $NF}' | sort -u > "${WORK}/need"

libs=("${SDK5}"/usr/lib/*.dylib "${SDK5}"/usr/lib/system/*.dylib)
for name in UIKit Foundation CoreGraphics QuartzCore CoreFoundation CoreText ImageIO AVFoundation CoreMedia CoreVideo CoreAudio AudioToolbox CoreLocation MobileCoreServices CFNetwork SystemConfiguration AssetsLibrary AddressBook AddressBookUI; do
    libs+=("${SDK5}/System/Library/Frameworks/${name}.framework/${name}")
done
for lib in "${libs[@]}"; do
    [[ -f "${lib}" && ! -L "${lib}" ]] || continue
    "${TC}/nm" -gU "${lib}" 2>/dev/null | awk '{print $NF}' || true
done | sort -u > "${WORK}/have"

[[ -s "${WORK}/have" ]] || { echo "no exports read from ${SDK5}" >&2; exit 1; }
missing="$(comm -23 "${WORK}/need" "${WORK}/have")"
if [[ -n "${missing}" ]]; then
    echo "armv7 slice imports symbols the iOS 5 runtime does not export:" >&2
    echo "${missing}" >&2
    exit 1
fi
echo "armv7 imports: $(wc -l < "${WORK}/need") symbols, all present in ${SDK5##*/}"
