#!/bin/bash
# Packs build/Blink.app into the files a release carries:
#
#   Blink.dmg       what people download: open it, drag Blink to Applications
#   Blink.zip       what an installed Blink fetches when it updates itself
#   checksums.txt   SHA-256 of both
#
#   Scripts/package.sh [output directory]      # default: build/dist
#
# The names carry no version on purpose, so that
# https://github.com/<owner>/<repo>/releases/latest/download/Blink.dmg always
# points at the newest one. The website links to exactly that.
#
# With SIGN_IDENTITY (the certificate the app was built with) the disk image is
# signed too, and with NOTARY_PROFILE both are notarized: see Scripts/notarize.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/dist}"
APP="build/Blink.app"
[ -d "$APP" ] || { echo "Build the app first: Scripts/build-app.sh" >&2; exit 1; }

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

mkdir -p "$OUT"
rm -f "$OUT/Blink.zip" "$OUT/Blink.dmg" "$OUT/checksums.txt"

# Before packing, so the zip and the disk image both hold the stapled app.
if [ -n "$NOTARY_PROFILE" ]; then
    Scripts/notarize.sh "$APP"
fi

ditto -c -k --keepParent "$APP" "$OUT/Blink.zip"

# The disk image holds the app next to a shortcut to Applications.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Blink.app"
ln -s /Applications "$STAGE/Applications"

# hdiutil sometimes finds the volume busy on a shared machine; trying again settles it.
made=0
for _ in 1 2 3; do
    if hdiutil create -volname Blink -srcfolder "$STAGE" -format UDZO -ov -quiet "$OUT/Blink.dmg"; then
        made=1
        break
    fi
    sleep 3
done
[ "$made" = 1 ] || { echo "Could not create the disk image." >&2; exit 1; }

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT/Blink.dmg"
fi
if [ -n "$NOTARY_PROFILE" ]; then
    Scripts/notarize.sh "$OUT/Blink.dmg"
fi

( cd "$OUT" && shasum -a 256 Blink.dmg Blink.zip > checksums.txt )
echo "Packaged:"
ls -lh "$OUT/Blink.dmg" "$OUT/Blink.zip"
