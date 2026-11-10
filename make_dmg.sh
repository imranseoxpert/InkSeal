#!/bin/bash
# Builds InkSeal.app and packages it as dist/InkSeal-<version>.dmg
# (drag-to-Applications installer).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="InkSeal"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/$APP_NAME-$VERSION.dmg"

[ "${SKIP_BUILD:-0}" = "1" ] || ./build.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "build/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
echo "Creating $DMG…"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "Verified."
shasum -a 256 "$DMG"
echo "Done → $DMG ($(du -h "$DMG" | cut -f1))"
