#!/bin/bash
# Launches the built app and has it check itself end to end: the overlay,
# hold and tap, arranging, content blocking inside a real page, and updating
# itself from a release.
#
#   Scripts/self-check.sh [output directory]
#
# Expects build/Blink.app (run Scripts/build-app.sh first). The report and
# screenshots land in the output directory.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/self-check}"
PORT="${PORT:-8765}"
FEED_PORT="${FEED_PORT:-8766}"
BUILT="build/Blink.app"
[ -x "$BUILT/Contents/MacOS/Blink" ] || { echo "Build the app first: Scripts/build-app.sh" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# The check ends with the app replacing itself, so it runs a copy and leaves
# the one in build/ as it was built.
RUN="$OUT/run"
mkdir -p "$RUN"
ditto "$BUILT" "$RUN/Blink.app"

# Stand-in releases for that copy to find, each claiming to be version 99:
#   newer      a later build of this app, which should be installed
#   impostor   some other app under the same file name, which should not
#   altered    this app with a file added after it was signed, which should not
FEED="$OUT/feed"
mkdir -p "$FEED"
publish() {
    local name="$1" stage="$FEED/stage"
    rm -rf "$stage"
    mkdir -p "$stage"
    ditto "$BUILT" "$stage/Blink.app"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 99.0.0" "$stage/Blink.app/Contents/Info.plist"
    if [ "$name" = impostor ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.example.Impostor" "$stage/Blink.app/Contents/Info.plist"
    fi
    codesign --force --sign - "$stage/Blink.app"
    if [ "$name" = altered ]; then
        echo "added after signing" > "$stage/Blink.app/Contents/Resources/extra.txt"
    fi
    ditto -c -k --keepParent "$stage/Blink.app" "$FEED/$name.zip"
    rm -rf "$stage"
    cat > "$FEED/$name.json" <<JSON
{
  "tag_name": "v99.0.0",
  "body": "A stand-in release for the self-check.",
  "draft": false,
  "prerelease": false,
  "assets": [
    {"name": "Blink.zip", "size": 1, "browser_download_url": "http://127.0.0.1:$FEED_PORT/$name.zip"}
  ]
}
JSON
}
publish newer
publish impostor
publish altered

# A page for the app to load, served the way a website would be, and the
# releases, served the way GitHub would.
python3 -m http.server "$PORT" --directory Tests/Fixtures > "$OUT/server.log" 2>&1 &
SERVER=$!
python3 -m http.server "$FEED_PORT" --directory "$FEED" > "$OUT/feed.log" 2>&1 &
FEED_SERVER=$!
trap 'kill "$SERVER" "$FEED_SERVER" 2>/dev/null || true' EXIT

for _ in $(seq 40); do
    curl -sf "http://127.0.0.1:$PORT/page.html" -o /dev/null \
        && curl -sf "http://127.0.0.1:$FEED_PORT/newer.json" -o /dev/null && break
    sleep 0.25
done
# The page loads one image through "localhost", which the check then blocks.
# Make sure that address works, or the block would appear to succeed anyway.
curl -sf "http://127.0.0.1:$PORT/page.html" -o /dev/null
curl -sf "http://localhost:$PORT/pixel.gif" -o /dev/null
curl -sf "http://127.0.0.1:$FEED_PORT/newer.zip" -o /dev/null

BLINK_SMOKE_URL="http://127.0.0.1:$PORT/page.html" \
BLINK_SMOKE_FIXTURES="$PWD/Tests/Fixtures" \
BLINK_SMOKE_REJECTED_FEEDS="http://127.0.0.1:$FEED_PORT/impostor.json,http://127.0.0.1:$FEED_PORT/altered.json" \
    "$RUN/Blink.app/Contents/MacOS/Blink" --smoke-test "$OUT" --update-feed "http://127.0.0.1:$FEED_PORT/newer.json"

# The app says it updated itself. Look at what is on disk rather than take its word.
installed="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$RUN/Blink.app/Contents/Info.plist")"
identifier="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$RUN/Blink.app/Contents/Info.plist")"
expected="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$BUILT/Contents/Info.plist")"
[ "$installed" = "99.0.0" ] || { echo "After updating, the copy is version $installed, not 99.0.0." >&2; exit 1; }
[ "$identifier" = "$expected" ] || { echo "After updating, the copy is $identifier, not $expected." >&2; exit 1; }
[ ! -e "$RUN/Blink.app/Contents/Resources/extra.txt" ] || { echo "The altered release was installed." >&2; exit 1; }
codesign --verify --deep --strict "$RUN/Blink.app"
echo "The copy updated itself to $installed and is intact."
rm -rf "$RUN" "$FEED"/*.zip
