# Button

Text and icon buttons for chrome, and the one filled `accent` button.

- Plain (`.bk-btn`): a verb, `button` type, no fill until hovered (`control-hover`) or pressed (`control-selected`).
- Icon (`.bk-iconbtn`): `size-control` square, an SF Symbol at 13pt in `ink-2`, `ink` on hover. Always give it a tooltip with its shortcut (“Add (⌘N)”).
- Accent (`.bk-btn--accent`): `accent` fill with `on-accent` text, `accent-pressed` while held. One per view: “Done” while arranging, “Allow Access…” in an empty state.
- Disabled: `ink-3`, no fill.
- Every button shows the `focus` ring when reached by keyboard.
