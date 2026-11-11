.PHONY: app run test test-browser check install icon site clean

# Build build/Blink.app (release).
app:
	Scripts/build-app.sh

# Build and launch, opening the overlay straight away.
run: app
	open build/Blink.app --args --show

# Unit tests for the platform-independent core.
test:
	swift test

# The JavaScript injected into pages, and the website, in a real browser
# (needs Playwright).
test-browser:
	Tests/Browser/run.sh

# Launch the built app and have it check itself end to end. Takes over the
# screen and the pointer for about a minute.
check: app
	Scripts/self-check.sh

# Copy the app into /Applications.
install: app
	rm -rf /Applications/Blink.app
	cp -R build/Blink.app /Applications/Blink.app

# Serve the website in docs/ at http://localhost:8000.
site:
	python3 -m http.server 8000 --directory docs

# Regenerate Resources/AppIcon.icns (needs Python with Pillow).
icon:
	python3 Scripts/make-icon.py

clean:
	rm -rf .build build
