#!/bin/bash
# Builds build/Blink.app from the Swift package.
#
#   Scripts/build-app.sh                 # release build for this Mac
#   UNIVERSAL=1 Scripts/build-app.sh     # Apple silicon + Intel
#   CONFIG=debug Scripts/build-app.sh
#
# The app is signed ad hoc unless SIGN_IDENTITY names a certificate. With one,
# it is signed the way Apple's notary service asks: hardened runtime, timestamp.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-org.blink-app.Blink}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Blink.app"

FLAGS=(-c "$CONFIG" --product Blink)
if [ "${UNIVERSAL:-0}" = "1" ]; then
    FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Blink" "$APP/Contents/MacOS/Blink"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/g" \
    -e "s/@BUILD@/$BUILD/g" \
    -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
        --entitlements Resources/Blink.entitlements "$APP"
fi
echo "Built $APP ($VERSION, build $BUILD)"
