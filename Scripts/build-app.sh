#!/bin/bash
# Builds build/Gander.app from the Swift package.
#
#   Scripts/build-app.sh                 # release build for this Mac
#   UNIVERSAL=1 Scripts/build-app.sh     # Apple silicon + Intel
#   CONFIG=debug Scripts/build-app.sh
#
# The app is signed ad hoc unless SIGN_IDENTITY names a certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-org.gander-app.Gander}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Gander.app"

FLAGS=(-c "$CONFIG" --product Gander)
if [ "${UNIVERSAL:-0}" = "1" ]; then
    FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Gander" "$APP/Contents/MacOS/Gander"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/g" \
    -e "s/@BUILD@/$BUILD/g" \
    -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
