#!/bin/bash
# Sends an app or a disk image to Apple's notary service and staples the
# ticket that comes back to it. A notarized download opens without macOS
# refusing it.
#
#   NOTARY_PROFILE=blink Scripts/notarize.sh build/Blink.app
#   NOTARY_PROFILE=blink Scripts/notarize.sh build/dist/Blink.dmg
#
# NOTARY_PROFILE names credentials saved once with
#   xcrun notarytool store-credentials blink --apple-id <you> --team-id <team>
# NOTARY_KEYCHAIN, if set, is the keychain file they were saved in.
#
# Apple only accepts what was signed with a Developer ID certificate:
# build with SIGN_IDENTITY set first.
set -euo pipefail

TARGET="${1:?usage: Scripts/notarize.sh <Blink.app | Blink.dmg>}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The service takes archives, not folders, so an app goes up as a zip.
UPLOAD="$TARGET"
if [ -d "$TARGET" ]; then
    UPLOAD="$WORK/upload.zip"
    ditto -c -k --keepParent "$TARGET" "$UPLOAD"
fi

AUTH=(--keychain-profile "$NOTARY_PROFILE")
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    AUTH+=(--keychain "$NOTARY_KEYCHAIN")
fi

# Judge by the status it prints, not by how it exits.
xcrun notarytool submit "$UPLOAD" "${AUTH[@]}" --wait --timeout 30m 2>&1 | tee "$WORK/log" || true
if ! grep -q "status: Accepted" "$WORK/log"; then
    id="$(sed -n 's/^ *id: *//p' "$WORK/log" | head -1)"
    if [ -n "$id" ]; then
        xcrun notarytool log "$id" "${AUTH[@]}" || true
    fi
    echo "Apple did not notarize $TARGET." >&2
    exit 1
fi

# Stapling fetches the ticket from Apple, and a dropped connection fails it
# even though notarizing worked, so try a few times before giving up.
for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$TARGET"; then
        exit 0
    fi
    [ "$attempt" -lt 5 ] || break
    echo "Stapling failed (attempt $attempt); trying again shortly." >&2
    sleep $(( attempt * 10 ))
done
echo "Apple notarized $TARGET, but the ticket could not be stapled." >&2
exit 1
