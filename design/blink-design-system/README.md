Blink is a Mac overlay: hold a key and the things you check all day appear over whatever you are doing; let go and they are gone. This system covers that overlay — the board of tiles, the chrome you get once it is pinned open, the launcher and the widgets. It is always dark, because it sits over whatever is on screen, and web pages inside tiles keep their own colours.

The drafts of the redesigned overlay are the **Overlay**, **First run** and **Hold and tap** pages under Drafts. **Directions** sets four looks side by side (Graphite, the one this system uses, then Liquid, Champagne and Porcelain), and **What changes** lists every change from Blink 0.1 and why.

## Principles

1. **The content is the interface.** While the key is held, show tiles and nothing else. Chrome — the `CommandBar`, a tile's head and tools — appears only once the overlay is pinned (tapped open), and a tile's tools only on the tile under the pointer.
2. **One clear accent.** `accent` means *on, new, or the one thing to do*: the primary button, unread and due counts, messages you sent, keyboard focus. Never use it for decoration, and never show more than one filled `accent` element per tile. Blink's amber, `brand`, lights the mark and nothing else.
3. **Arrive fast, leave faster.** Blink must feel like a glance. Things arrive in `duration-fade` with `ease-arrive` and leave in `duration-leave` with `ease-leave`; nothing makes you wait to get back to work. See **Motion**.
4. **Frosted glass, not cards.** Every surface is the same smoked glass: the desktop behind it blurred by `glass-blur` and lifted a little by `glass-saturate`, a faint white from `glass-fill-top` to `glass-fill-bottom`, a dark `glass-shade` so text always reads, a soft `specular` sheen across the top and a quiet rim that runs from `rim-light` at the top-left and bottom-right corners to `rim-dark` between them. Floating glass (the command bar, the launcher, menus) uses the deeper `glass-shade-raised`, because it often sits over a white page. Never put a solid fill, a colour or a thick border on glass.
5. **Start somewhere.** A new board offers `Templates`, never an empty state.

## Voice

- Sentence case everywhere. Buttons are verbs: “Add”, “Arrange”, “Done”, “Allow Access…”. An ellipsis means another step follows.
- Hints are one line and name the key: “⌥` or esc to close”, “Drag a tile to move it, or its edge to resize”.
- Describe what something is for, plainly: “The time in the places you care about”, “What is due, ready to tick off”, “A scratchpad that is always there”, “Keep a document within reach”.
- Name people as the person's contacts do; show initials, never photos.
- Name sites by their host (“github.com”), files by their name.
- No emoji, no exclamation marks, no “Oops”. Errors say what happened and what to do.

## Colour

- Ground: the board sits on the person's own desktop under `scrim` and a `vignette` toward the edges. Previews paint a cool slate wallpaper from `wall-1` to `wall-4` over `desktop`; `wall-3`, the pale haze, is the brightest ground glass ever meets, so every text colour is checked on glass over it. Never put text straight on the desktop except the command bar's hint, in `ink-2`, with `shadow-text`.
- Dimming: `scrim` is part of legibility. At its value, every text colour passes 4.5:1 on glass even with a white or black window behind Blink; the Appearance setting may make it darker, never lighter.
- Surfaces: every surface is glass (see Principles). `tile` and `tile-raised` are flat stand-ins for places glass cannot be drawn. Web pages sit `web-inset` inside their glass, so the glass frames the page; before it paints, `web-ground`.
- Text: `ink` for titles and values, `ink-2` for details and hints, `section` for `caption` labels, `ink-3` only for placeholders and disabled labels.
- Controls: rest on `control`, `control-hover` under the pointer, `control-selected` when chosen.
- Signals: `late` for overdue and the calendar's now line, `up`/`down` for trends — always with a word or ▲▼, never colour alone. `cool` marks night in the clock and websites in the launcher.
- Messages: received bubbles in `bubble-in`, sent ones in `accent` with `on-accent` text. Avatars are tinted glass, each person a different one of `cool`, `warm`, `up` and `accent`.
- Calendar events are tinted glass in their calendar's colour (`cool`, `warm`), with a 2px edge in the full colour.
- Brand: `brand` (Blink's amber) is the lit tile of the mark. Nowhere else.
- Edges: `stroke` around tiles and panels, `stroke-control` around the command bar, `stroke-strong` only for a tile being arranged and for keycaps.

## Type

Blink sets everything in **Geist**, with **Geist Mono** for keys. Both are under the SIL Open Font License: ship the files in the app (`fonts/`) and register them at launch; never fall back to the system font silently. Figures (`clock`, `date`) use Geist at `figure-weight` so the clock reads light and exact.

- Chrome: `label` in the command bar, `button` for text buttons, `hint` for one-line hints, `caption` (uppercase, tracked) over groups of rows, `keycap` inside keys.
- Tiles: `row-title` and `row-detail` for every two-line row; `tile-title` in a tile's head; `bubble` in messages; `search` in the launcher's field.
- Figures: `clock`, `date` and `count`, always with tabular figures (`font-variant-numeric: tabular-nums`) so times do not jiggle as they change.
- Truncate a row's detail before its title; never truncate a place name to a single letter — stack it under the time instead (see `ClockWidget`).

## Space, size and shape

- The board is inset `canvas-padding` from the screen and tiles sit `tile-gap` apart. Pinned, the top inset grows to `chrome-inset` to make room for the `CommandBar`.
- Inside tiles use `space-m`; between controls `space-s`; between an icon and its label `space-xs`.
- Heights: `size-bar` for the command bar, `size-control` for its buttons and a tile's tools, `size-segment` for segments, `size-row` for two-line rows, `size-avatar` for people, `size-keycap` for keys.
- Radii: `radius-tile` for tiles (people can change it; derive inner radii from it), `radius-panel` for the launcher, `radius-row` for rows and events, `radius-bubble` for messages, `radius-pill` for every capsule and avatar, `radius-key` for keycaps.

## Depth

- `shadow-tile` on every tile at rest; `shadow-lifted` on the tile being dragged; `shadow-bar` on the command bar and tile tools; `shadow-panel` on the launcher; `shadow-thumb` under the selected segment, a droplet of glass on its track.
- Text on glass carries `shadow-text`; text on web pages never does.
- Radii are concentric: anything inset inside a tile takes `radius-tile` minus its inset.
- Never stack two floating layers over the same tile: the launcher replaces the tile tools while open.

## States

- Hover: fill `control-hover`; a tile's head appears after `hover-delay`.
- Pressed: fills step to `control-selected`; an `accent` fill dims to `accent-pressed`.
- Focus: a 2px `focus` ring, 2px outside, on every control reached by keyboard.
- Disabled: `ink-3` text, no fill change, no pointer.
- Selected: `control-selected` fill.

## Iconography

Blink uses **Lucide** (ISC licence): line icons on a 24px grid, drawn at a 1.75px stroke, shown at 14px in the command bar, tile heads and rows and 16px in the launcher. They are under Icons, single ink, tinted in code: `ink-2` at rest, `ink` on hover, `accent` when they mean something is on. Never mix in another set, fill them, or draw a stand-in; add any new icon from Lucide at the same stroke.

The names Blink uses: plus, settings, search, chevron-left, chevron-right, rotate-cw, ellipsis, clock, calendar, list-checks, sticky-note, file-text, globe, sun, moon, x, columns-3, layout-dashboard, move, check, message-circle, arrow-up.

The mark is three tiles, one of them lit (Logos). Use `blink-mark.svg` on dark grounds and the single-ink `blink-mark-template.svg` where the system tints it (the menu bar).

## Motion

Every moment's timing is in **Motion**. In short: arrive in `duration-fade` (`ease-arrive`, tiles staggered by `stagger` from the pointer outward), leave in `duration-leave` (`ease-leave`, all at once), move things with `spring-select` or `spring-reflow`, and with Reduce Motion on, replace every movement with a crossfade of the same length.
