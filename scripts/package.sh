#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-signed}"
[[ "$mode" == signed || "$mode" == --unsigned ]] || { echo 'usage: package.sh [--unsigned]' >&2; exit 1; }
make test
make inspect-unsigned
version=$(awk -F': ' '$1 == "Version" {print $2}' packaging/DEBIAN/control)
[[ "$version" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] || { echo 'invalid package version' >&2; exit 1; }
stage=build/package-stage
rm -rf "$stage"
mkdir -p "$stage/DEBIAN" "$stage/var/jb/Applications" "$stage/var/jb/usr/bin" "$stage/var/jb/usr/lib" "$stage/var/jb/Library/LaunchDaemons"
cp packaging/DEBIAN/* "$stage/DEBIAN/"
cp -R build/ios/Shiro.app "$stage/var/jb/Applications/"
cp build/ios/shirod "$stage/var/jb/usr/bin/"
cp build/ios/shirostatus*.dylib status/shirostatus.plist "$stage/var/jb/usr/lib/"
cp packaging/launchd.sh "$stage/var/jb/usr/lib/shiro-launchd.sh"
cp packaging/status.sh "$stage/var/jb/usr/lib/shiro-status.sh"
cp packaging/com.shiro.shirod.plist "$stage/var/jb/Library/LaunchDaemons/"
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm" "$stage/var/jb/Applications/Shiro.app/Shiro" "$stage/var/jb/usr/bin/shirod" "$stage/var/jb/usr/lib/"*.dylib
output="build/shiro-${version}.deb"
if [[ "$mode" == --unsigned ]]; then
    output="build/shiro-${version}-unsigned.deb"
else
    signer="${SHIRO_LDID:-${SHIRO_TC:-${THEOS:?set THEOS or SHIRO_LDID}/toolchain/linux/iphone/bin}/ldid}"
    [[ -x "$signer" ]] || { echo 'missing SHIRO_LDID signer' >&2; exit 1; }
    "$signer" -S "$stage/var/jb/Applications/Shiro.app/Shiro"
    "$signer" -S "$stage/var/jb/usr/bin/shirod"
    "$signer" -S "$stage/var/jb/usr/lib/shirostatus.dylib"
    "$signer" -S "$stage/var/jb/usr/lib/shirostatus-modern.dylib"
fi
dpkg-deb --root-owner-group -Zgzip --build "$stage" "$output"
python3 scripts/verify_package.py "$output" "$mode"
