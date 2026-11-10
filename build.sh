#!/bin/bash
# Builds InkSeal.app into ./build. Works with Xcode or with just the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="InkSeal"
APP="build/$APP_NAME.app"

# With only the Command Line Tools, the newest SDK declares SwiftUI's @State as a macro whose
# plugin ships with Xcode. Fall back to the newest SDK that doesn't need it.
if [ -z "${SDKROOT:-}" ] && ! xcode-select -p 2>/dev/null | grep -q "Xcode"; then
  sdk="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
  [ -n "$sdk" ] && export SDKROOT="$sdk"
fi
[ -n "${SDKROOT:-}" ] && echo "Using SDK: $SDKROOT"

echo "Compiling…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  echo "Rendering icon…"
  rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
  swift Tools/make_icon.swift build/icon_1024.png >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "(ad-hoc signing skipped)"
echo "Done → $APP"
