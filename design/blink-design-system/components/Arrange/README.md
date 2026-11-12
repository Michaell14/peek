# Arrange

Moving and resizing tiles. Arrange (`⌘E`) replaces Edit.

- Tiles stay recognisable: content dims to 55%, edges brighten to `stroke-strong`, and small handles appear at the middle of each edge with a grip in the bottom-right corner.
- The remove button sits half outside the top-left corner, in `tile-raised`, so it never covers the tile's name.
- Dragging lifts the tile: scale 1.02, `shadow-lifted`, a 1.5px `accent` edge. Other tiles make room with `spring-reflow`; a dashed slot shows where it will land. In Freeform, a 1px `accent` guide flashes along an edge it snaps to.
- “Done” in the `CommandBar`, `esc` or `⌘E` ends arranging.
