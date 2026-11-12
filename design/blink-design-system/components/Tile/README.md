# Tile

One thing you check: a page, a widget or a file, on smoked glass.

- `tile` (glass on the Mac: `glass-tint` over the blur), `stroke` hairline, `shadow-tile`, `radius-tile`. Web tiles show the page on `web-ground`.
- Under a resting pointer, after `hover-delay`, a head fades in over the content: a chip with the tile's icon and name on the left, its tools on the right. It leaves in `duration-leave` when the pointer does. Nothing in the tile moves to make room.
- Web tools: back, forward, reload (its ring shows the time to the next automatic refresh) and more. Widgets show only what they need (a filter, nothing at all).
- While a page loads, a 2px `accent` line runs along the top; the new page crossfades in `duration-fade`.
- The consumer provides the content, its name and icon, and the tools.
