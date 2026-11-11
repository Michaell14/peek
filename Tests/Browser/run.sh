#!/bin/bash
# Runs the scripts Blink injects into web pages, and the website in docs/,
# in a real browser.
# Needs Node with Playwright: npm install --no-save playwright && npx playwright install chromium
# Set BROWSER=webkit to test in the engine closest to the app's own.
set -euo pipefail
cd "$(dirname "$0")/../.."

SCRIPTS="$(mktemp -t blink-scripts.XXXXXX)"
trap 'rm -f "$SCRIPTS"' EXIT
swift run blink-scripts > "$SCRIPTS"
node Tests/Browser/picker.test.mjs "$SCRIPTS"

# The website in docs/, including its hold-to-blink demo.
node Tests/Browser/site.test.mjs
