#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
make app-unsigned
signer="${SHIRO_LDID:-${SHIRO_TC:-${THEOS:?set THEOS or SHIRO_LDID}/toolchain/linux/iphone/bin}/ldid}"
tc="${SHIRO_TC:-${THEOS:?set THEOS or SHIRO_TC}/toolchain/linux/iphone/bin}"
[[ -x "$signer" ]] || { echo 'missing SHIRO_LDID signer' >&2; exit 1; }
"$tc/lipo" -info build/ios/Shiro.app/Shiro
if [[ -n "${SHIRO_SDK_V5:-}" ]]; then
    SHIRO_TC="$tc" bash scripts/check_legacy_symbols.sh build/ios/Shiro.app/Shiro
fi
stage=build/ipa-stage
rm -rf "$stage"
mkdir -p "$stage/Payload"
cp -R build/ios/Shiro.app "$stage/Payload/"
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/Payload/Shiro.app/Shiro"
"$signer" -S "$stage/Payload/Shiro.app/Shiro"
version=$(python3 -c 'import plistlib; print(plistlib.load(open("packaging/Info.plist", "rb"))["CFBundleShortVersionString"])')
output="Shiro-${version}.ipa"
rm -f "build/$output"
(cd "$stage" && zip -q -r "../$output" Payload)
python3 scripts/verify_ipa.py "build/$output"
