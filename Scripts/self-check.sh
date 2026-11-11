#!/bin/bash
# Launches the built app and has it check itself end to end: the overlay,
# hold and tap, arranging, and content blocking inside a real page.
#
#   Scripts/self-check.sh [output directory]
#
# Expects build/Blick.app (run Scripts/build-app.sh first). The report and
# screenshots land in the output directory.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/self-check}"
PORT="${PORT:-8765}"
APP="build/Blick.app/Contents/MacOS/Blick"
[ -x "$APP" ] || { echo "Build the app first: Scripts/build-app.sh" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"

# A page for the app to load, served the way a website would be.
python3 -m http.server "$PORT" --directory Tests/Fixtures > "$OUT/server.log" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

for _ in $(seq 40); do
    curl -sf "http://127.0.0.1:$PORT/page.html" -o /dev/null && break
    sleep 0.25
done
# The page loads one image through "localhost", which the check then blocks.
# Make sure that address works, or the block would appear to succeed anyway.
curl -sf "http://127.0.0.1:$PORT/page.html" -o /dev/null
curl -sf "http://localhost:$PORT/pixel.gif" -o /dev/null

BLICK_SMOKE_URL="http://127.0.0.1:$PORT/page.html" \
BLICK_SMOKE_FIXTURES="$PWD/Tests/Fixtures" \
    "$APP" --smoke-test "$OUT"
