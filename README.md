# Blink

**Hold a key to glance at the things you check all day. Let go and you are back where you were.**

Blink is a free, open-source macOS menu bar app. It keeps websites, local files and small widgets
loaded in a full-screen overlay that appears while you hold a shortcut — over any app, including
full-screen ones — and disappears when you release it.

- **Hold** the shortcut (`fn` by default) to peek. Release to return.
- **Tap** the shortcut to keep the overlay open and use it. Tap again or press `esc` to close.

![The Blink overlay showing a clock, reminders, a web dashboard and a calendar](docs/screenshot.png)

## What it does

| | |
|---|---|
| **Websites** | Any site, in WebKit. Logins persist, and sign-in pop-ups ("Sign in with Google") open in a window of their own that reports back to the page. Back/forward/reload, zoom, mobile-site mode, auto-refresh. |
| **Local files** | PDF and HTML. Add from the launcher or Finder's *Open With → Blink*. Reloads when the file changes. |
| **Widgets** | Clock (multiple time zones), Calendar (day timeline or next 7 days), Reminders (today / scheduled / overdue / all, tick off, add), Notes. |
| **Less noise** | Blocks third-party ads and trackers, hides cookie banners, and lets you click page elements to hide them for good. Accepts your own Adblock Plus-style filters. |
| **Layouts** | *Flow* packs tiles into columns for you; *Freeform* lets you drag and resize anywhere with snapping. |
| **Displays** | Opens on the display with the pointer, the active window, or one you pick. One layout everywhere, or one per display. |
| **Shortcut** | Any key combination, or modifier keys alone — including a specific left or right one (`Right ⌘`, `fn`). |
| **Hand off** | Open any tile in your browser or its default app from its `…` menu. |

Your layouts and browsing data stay on your Mac. Blink has no account, analytics or server.

## Install

Requires macOS 14 or later.

**Download:** get [Blink.dmg](https://github.com/Michaell14/peek/releases/latest/download/Blink.dmg),
open it, and drag Blink into Applications. Releases are not notarized by Apple yet, so the first
time you open it macOS will refuse: go to *System Settings → Privacy & Security* and choose
**Open Anyway**. That is needed once.

**Build from source** (needs Xcode 16 or its command line tools):

```bash
git clone https://github.com/Michaell14/peek.git blink
```

```bash
cd blink && make install
```

That builds `build/Blink.app` and copies it to `/Applications`. Use `make run` to build and launch
without installing.

### Updates

Once a day Blink asks GitHub for the newest release and, if it is newer than the running copy,
offers to install it and start again. *Check for Updates…* in the menu bar menu asks straight
away, and *Settings → About* turns the daily check off. The request carries nothing about you or
your Mac.

Before a download replaces the running app, Blink checks that it came over HTTPS from this
project's releases, that it is this app and the version that was offered, that nothing in it has
changed since it was signed, and, if the running copy was signed by an identifiable developer,
that the new one was signed by the same one. Releases are currently signed ad hoc, which names no
developer, so that last check does not apply yet.

## Using it

Blink lives in the menu bar (the three-tile icon) and has no Dock icon. On first launch it opens
with a starter layout.

With the overlay open (tap the shortcut), the controls are in the top-right corner:

| | |
|---|---|
| `+` or `⌘N` | Open the palette: type an address or filter the list, `↑` `↓` to choose, `↩` to add |
| **Edit** or `⌘E` | Move, resize and remove tiles |
| **Flow / Freeform** | Switch layout mode; tiles stay where they are |
| Hover a tile | Back, forward, reload and a `…` menu with everything else |
| `⌘R` `⌘[` `⌘]` | Reload / back / forward for the web tile under the pointer |
| `⌘`-click a link | Open it in your browser instead |
| `esc` | Back out one step, then close |

To hide part of a page, choose **Hide Elements…** from a web tile's `…` menu and click what you
want gone. `↑` widens the selection to the surrounding element and `↓` narrows it again. Choices
are remembered per site; **Show Hidden Elements** brings them back.

### Permissions

Blink asks only for what a feature needs, and only when you use it.

| Permission | Needed for |
|---|---|
| Calendars / Reminders | Those two widgets |
| Input Monitoring | The default shortcut, `fn`, and any other made of modifier keys alone or a specific left/right key. Blink looks for the shortcut and does not record what you type. |

macOS only shows `fn` to apps allowed under Input Monitoring, so Blink explains this and asks when
it first opens. If you would rather not allow it, record an ordinary combination in Settings, such
as `⌥` + `` ` ``: those need no permission. (Settings saved by earlier versions with `⌥` + `` ` ``,
the old default, move to `fn` once.)

With `fn` as the shortcut, set *System Settings → Keyboard → Press 🌐 key to* **Do Nothing**, or
macOS will also run its own action (the emoji picker, by default) each time. Blink waits a moment
before it reacts to `fn`, so `fn`-arrow and other combinations that start with it do not flash the
overlay.

Builds are signed ad hoc. macOS ties permissions to the signature, so it asks again after each
rebuild, and may ask again after an update.

## How it is built

```
Sources/
  BlinkCore/   Models, layout, shortcut logic, content-blocking rules. Plain
                Foundation; builds and is tested on Linux as well as macOS.
  Blink/       The app: AppKit overlay and tiles, WebKit, SwiftUI widgets
                and settings.
  blink-scripts/  Dev tool that prints the JavaScript injected into pages.
Tests/
  BlinkCoreTests/  Unit tests for the core.
  Browser/          Runs the injected JavaScript, and the website, in a real browser.
docs/               The website. Plain HTML, CSS and JavaScript; no build step.
```

A few decisions worth knowing about:

- **The overlay is a non-activating panel.** Showing it never makes Blink the frontmost app, so
  the app, space and text field you were in stay exactly as they were.
- **Tiles stay loaded while hidden.** That is what makes a peek instant, and why auto-refresh can
  keep pages current in the background. Audio never starts without a click.
- **Hover is sampled, not event-driven.** Because Blink is never frontmost, the system does not
  reliably tell its window when the pointer moves, so the overlay checks where the pointer is a
  few times a second while it is open.
- **Ordinary shortcuts use the system hot-key service**, which needs no permission. Only shortcuts
  it cannot express fall back to watching keyboard events.
- **Blocking is third-party only.** A tracker is blocked on other sites, but its own dashboard
  still works when you open it as a tile.
- **Saved data is never thrown away.** An unreadable layout file is set aside rather than
  overwritten, and tiles from a newer version are skipped without losing the rest.

### Development

```bash
make test
```

```bash
make test-browser
```

```bash
make check
```

`make test` runs the core's unit tests. `make test-browser` runs the JavaScript that Blink
injects into pages, and the website's own interactions, in a real browser (needs Node and
Playwright).

`make check` launches the built app with a throwaway layout and has it check itself, using
simulated clicks, drags and key presses: showing and hiding, hold and tap, moving, resizing and
reordering tiles, typing into a page, content blocking and element hiding inside a real page, file
tiles, widgets and per-display layouts. It takes over the screen and the pointer for about a
minute, and writes a report and screenshots to `build/self-check`.

CI runs all three on every push.

Other switches: `--show` opens the overlay at launch; `--data-dir <path>` (or `BLINK_DATA_DIR`)
keeps layouts somewhere other than `~/Library/Application Support/Blink`.

## The website

`docs/` holds Blink's website. One Mac screen, drawn in HTML, stays pinned while Blink's story
plays on it: someone mid-sentence, the overlay coming up while fn is held, a website refreshing,
widgets, a PDF, arranging tiles, and a full-screen app. Each scroll gesture (or arrow key) plays the
next step through at its own pace and rests there, with a caption that fills in as it plays; after
the last step the page scrolls normally. The page is also its own demo: hold Space at any point and the
overlay opens on the screen, or over the page itself further down. On phones, and with reduced
motion, the story is a list of stills instead.

It is plain HTML, CSS and JavaScript, loads nothing from anywhere else, and needs no build step.
The two typefaces, Schibsted Grotesk and Fraunces, are served from `docs/fonts` under the SIL Open
Font License, and the wallpaper is a small SVG.

Earlier design directions for the site are kept in `drafts/`; each folder is a standalone page.

```bash
make site
```

serves it at `http://localhost:8000`. To publish it with GitHub Pages, choose *Deploy from a
branch* in the repository's Pages settings and pick the `/docs` folder.

## Releasing

A release is what the website's download button serves and what installed copies update to.

Releases happen by themselves: whenever a change to the app (`Sources`, `Resources`, the package
manifest or the build scripts) lands on the default branch, the Release workflow publishes the next
patch version, so `0.1.0` is followed by `0.1.1`. A pull request that only touches the website,
tests or docs publishes nothing. Releases run one at a time, so two merges in quick succession get
two numbers.

To pick the number yourself, for a bigger step, open *Actions → Release → Run workflow* and type a
version such as `0.2.0`, or from a terminal:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Automatic releases carry on from the highest version published.

The workflow tests and builds a universal app, runs the same end-to-end self-check as CI on it
(`Scripts/self-check.sh`), packs it with `Scripts/package.sh`, and publishes `Blink.dmg` (for
people), `Blink.zip` (for the app's own updates) and their checksums. If the self-check fails,
nothing is published. A copy of Blink only offers an update that is newer than itself.

### Signing and notarizing

Without a certificate the release is signed ad hoc and macOS refuses to open the download until it
is allowed in *Privacy & Security*. The workflow signs with a Developer ID and has Apple notarize
the app and the disk image when the repository has these five secrets (*Settings → Secrets and
variables → Actions*). They need a paid Apple Developer Program membership.

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12` | A *Developer ID Application* certificate with its private key, exported from Keychain Access as a `.p12` and base64-encoded (`base64 -i certificate.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting it |
| `APPLE_ID` | The Apple ID of the developer account |
| `APPLE_TEAM_ID` | Its ten-character team ID, from developer.apple.com → Membership |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID, made at account.apple.com |

To do the same by hand, save the credentials once with `xcrun notarytool store-credentials blink`,
then:

```bash
SIGN_IDENTITY="Developer ID Application: …" UNIVERSAL=1 Scripts/build-app.sh
```

```bash
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=blink Scripts/package.sh
```

This path has not yet been run with a real certificate.

## Not there yet

- Passkeys in web tiles. macOS only offers them to apps holding a browser entitlement that Apple
  grants case by case.
- Browser extensions.
- Showing other apps' windows as tiles.
- A stocks widget.
- Releases signed with an Apple developer certificate and notarized. Until then macOS asks you to
  confirm the first launch, and may ask for Input Monitoring again after an update.

## Origin

Blink was written from scratch as an open alternative to [Peek](https://peek.zone), a commercial
app with the same hold-to-glance idea, working only from its public description. It shares no
code, assets or name with it, and is not affiliated with its makers.

## License

[MIT](LICENSE)
