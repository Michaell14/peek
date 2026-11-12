Blink is a Mac overlay: hold a key and the things you check all day appear over whatever you are doing; let go and they are gone. This system covers that overlay — the board of tiles, the chrome you get once it is pinned open, the launcher and the widgets. It is always dark, because it sits over whatever is on screen, and web pages inside tiles keep their own colours.

The drafts of the redesigned overlay are the **Overlay** and **Hold and tap** pages under Drafts; **What changes** lists every change from Blink 0.1 and why.

## Principles

1. **The content is the interface.** While the key is held, show tiles and nothing else. Chrome — the `CommandBar`, a tile's head and tools — appears only once the overlay is pinned (tapped open), and a tile's tools only on the tile under the pointer.
2. **One warm light.** `accent` means *on, now, or the one thing to do*: the selected layout mode, the primary button, the count of what is due, keyboard focus. It is the lit tile in the mark. Never use it for decoration, and never show more than one filled `accent` element at a time.
3. **Arrive fast, leave faster.** Blink must feel like a glance. Things arrive in `duration-fade` with `ease-arrive` and leave in `duration-leave` with `ease-leave`; nothing makes you wait to get back to work. See **Motion**.
4. **Glass, not cards.** Tiles are smoked glass (`glass-tint` over the blurred desktop) with a `stroke` hairline and `shadow-tile`. Depth comes from blur and shadow, never from borders thicker than a hairline or from colour fills.

## Voice

- Sentence case everywhere. Buttons are verbs: “Add”, “Arrange”, “Done”, “Allow Access…”. An ellipsis means another step follows.
- Hints are one line and name the key: “fn or esc to close”, “Drag a tile to move it, or its edge to resize”.
- Describe what something is for, plainly: “The time in the places you care about”, “What is due, ready to tick off”, “A scratchpad that is always there”, “Keep a document within reach”.
- Name sites by their host (“github.com”), files by their name.
- No emoji, no exclamation marks, no “Oops”. Errors say what happened and what to do.

## Colour

- Ground: the board sits on `desktop` (the real desktop, blurred) under `scrim` and a `vignette` toward the edges. Never put text straight on `desktop` except the command bar's hint, in `ink-2`.
- Surfaces: tiles are `tile`; anything floating above tiles (command bar, launcher, menus, the remove button) is `tile-raised` with `shadow-bar` or `shadow-panel`. Web tiles show the page; before it paints, `web-ground`.
- Text: `ink` for titles and values, `ink-2` for details and hints, `section` for `caption` labels, `ink-3` only for placeholders and disabled labels.
- Controls: rest on `control`, `control-hover` under the pointer, `control-selected` when chosen. The selected layout segment is the one control that may use `accent` text.
- Signals: `late` for overdue and the calendar's now line, `up`/`down` for trends — always with a word or ▲▼, never colour alone. `cool` marks night in the clock and websites in the launcher.
- Edges: `stroke` around tiles and panels, `stroke-control` around the command bar, `stroke-strong` only for a tile being arranged and for keycaps.

## Type

Blink uses the system font: SF Pro for text, SF Pro Rounded for figures and keycaps. Ship no font files.

- Chrome: `label` in the command bar, `button` for text buttons, `hint` for one-line hints, `caption` (uppercase, tracked) over groups of rows, `keycap` inside keys.
- Tiles: `row-title` and `row-detail` for every two-line row; `tile-title` in a tile's head; `search` in the launcher's field.
- Figures: `clock`, `date` and `count`, always with tabular figures (`font-variant-numeric: tabular-nums`) so times do not jiggle as they change.
- Truncate a row's detail before its title; never truncate a place name to a single letter — stack it under the time instead (see `ClockWidget`).

## Space, size and shape

- The board is inset `canvas-padding` from the screen and tiles sit `tile-gap` apart. Pinned, the top inset grows to `chrome-inset` to make room for the `CommandBar`.
- Inside tiles use `space-m`; between controls `space-s`; between an icon and its label `space-xs`.
- Heights: `size-bar` for the command bar, `size-control` for its buttons and a tile's tools, `size-segment` for segments, `size-row` for two-line rows, `size-keycap` for keys.
- Radii: `radius-tile` for tiles (people can change it; derive inner radii from it), `radius-panel` for the launcher, `radius-row` for rows and events, `radius-pill` for every capsule, `radius-key` for keycaps.

## Depth

- `shadow-tile` on every tile at rest; `shadow-lifted` on the tile being dragged; `shadow-bar` on the command bar and tile tools; `shadow-panel` on the launcher.
- Never stack two floating layers over the same tile: the launcher replaces the tile tools while open.

## States

- Hover: fill `control-hover`; a tile's head appears after `hover-delay`.
- Pressed: fills step to `control-selected`; an `accent` fill dims to `accent-pressed`.
- Focus: a 2px `focus` ring, 2px outside, on every control reached by keyboard.
- Disabled: `ink-3` text, no fill change, no pointer.
- Selected: `control-selected` fill; the layout mode's selected segment also takes `accent` text.

## Iconography

Blink uses SF Symbols at regular weight: 13pt in the command bar and tile tools, 15pt in launcher rows inside a 28pt tinted square. Previews here draw simple 1.5px line icons in their place, since SF Symbols cannot be shipped in a web page; on the Mac always use the symbol (`plus`, `gearshape`, `chevron.left`, `chevron.right`, `arrow.clockwise`, `ellipsis`, `clock`, `calendar`, `checklist`, `note.text`, `doc`, `globe`, `magnifyingglass`, `xmark`, `sun.max`, `moon`).

The mark is three tiles, one of them lit (Logos). Use `blink-mark.svg` on dark grounds and the single-ink `blink-mark-template.svg` where the system tints it (the menu bar).

## Motion

Every moment's timing is in **Motion**. In short: arrive in `duration-fade` (`ease-arrive`, tiles staggered by `stagger` from the pointer outward), leave in `duration-leave` (`ease-leave`, all at once), move things with `spring-select` or `spring-reflow`, and with Reduce Motion on, replace every movement with a crossfade of the same length.
