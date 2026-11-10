#!/bin/bash
# Builds a universal (Apple Silicon + Intel) InkSeal.app into ./build.
# Works with Xcode or with just the Command Line Tools.
#   ./build.sh               universal build
#   ARCHS=arm64 ./build.sh   single-architecture build (faster)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="InkSeal"
APP="build/$APP_NAME.app"
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="14.0"

# With only the Command Line Tools, the newest SDK declares SwiftUI's @State as a macro whose
# plugin ships with Xcode. Fall back to the newest SDK that doesn't need it.
if [ -z "${SDKROOT:-}" ] && ! xcode-select -p 2>/dev/null | grep -q "Xcode"; then
  sdk="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
  [ -n "$sdk" ] && export SDKROOT="$sdk"
fi
[ -n "${SDKROOT:-}" ] && echo "Using SDK: $SDKROOT"

BINARIES=()
for arch in $ARCHS; do
  echo "Compiling for $arch…"
  triple="$arch-apple-macosx$MIN_MACOS"
  swift build -c release --triple "$triple" --scratch-path ".build/$arch"
  BINARIES+=("$(swift build -c release --triple "$triple" --scratch-path ".build/$arch" --show-bin-path)/$APP_NAME")
done

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${#BINARIES[@]}" -gt 1 ]; then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"
fi
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
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "Done → $APP"
