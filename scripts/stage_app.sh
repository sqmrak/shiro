#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python="$1"
stage=build/ios/Shiro.app
rm -rf "$stage"
mkdir -p "$stage"
cp build/ios/Shiro "$stage/Shiro"
cp packaging/Info.plist resources/shiro/*.pem assets/shiro_fox.png LICENSE "$stage/"
cp resources/fonts/Rubik-*.ttf resources/fonts/Rubik-LICENSE.txt "$stage/"
cp assets/glyph-*.png assets/sticker-popup*.png assets/sqmrak.jpg assets/qwertyu1opz.png assets/cloudflare.png "$stage/"
"$python" scripts/icons.py
