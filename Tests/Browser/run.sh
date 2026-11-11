#!/bin/bash
# Runs the scripts Gander injects into web pages in a real browser.
# Needs Node with Playwright: npm install --no-save playwright && npx playwright install chromium
# Set BROWSER=webkit to test in the engine closest to the app's own.
set -euo pipefail
cd "$(dirname "$0")/../.."

SCRIPTS="$(mktemp -t gander-scripts.XXXXXX)"
trap 'rm -f "$SCRIPTS"' EXIT
swift run gander-scripts > "$SCRIPTS"
node Tests/Browser/picker.test.mjs "$SCRIPTS"
