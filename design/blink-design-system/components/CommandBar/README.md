# CommandBar

The controls you get once Blink is pinned open, in one capsule centred at the top of the board.

- Appears only while pinned; a glance shows no chrome at all. It drops 6px into place in `duration-move` after the tiles have arrived, and leaves with them in `duration-leave`.
- Order, left to right: the mark and name; Add (`⌘N`), Arrange (`⌘E`), Settings; then the `esc` hint. Separators split the groups. There is no layout switch: tiles always pack into columns.
- `tile-raised` behind `blur`, `stroke-control` hairline, `shadow-bar`, `size-bar` high, `radius-pill`.
- While arranging, Arrange becomes the accent “Done”, the only accent fill on screen.
- Centre it over the board, `space-m` from the top edge of the screen, inside `chrome-inset`.
