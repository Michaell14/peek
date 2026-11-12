# What changes

These are the drafts for Blink's next look, set against what 0.1 does today. The **Overlay** page puts them together; each component page shows one.

## The command bar replaces the corner toolbar

**Now:** the brand and “fn or esc to close” hug the top-left corner; Flow/Freeform, `+`, Edit and the gear hug the top-right, 6px from the edge, all at the same weight.

**Draft:** one `CommandBar` capsule centred at the top while pinned: the mark and name, the layout switch, then Add, Arrange and Settings, with the `esc` hint at its end. One place to look, grouped by what the controls do, and clear of the menu bar's corners where the pointer often rests. It only exists while pinned, so a glance stays chrome-free.

## Tiles get a head on hover

**Now:** widgets have no names, and web tiles show a floating tool pill over the page.

**Draft:** under a resting pointer, a tile shows a slim head: its icon and name on the left, its tools on the right (back, forward, reload, more for pages; a filter for reminders). The head floats over the content in `tile-raised` glass, so nothing reflows, and goes as soon as the pointer leaves.

## Arrange keeps the content visible

**Now:** Edit turns every tile into a grey slab with a centred label, white corner brackets and edge bars, and the remove button covers the tile's title.

**Draft:** **Arrange** (the new name for Edit) dims content to 55% so you still recognise each tile, draws small handles at the middle of each edge and a grip in the corner, and moves the remove button half outside the top-left corner. The tile being dragged lifts (`shadow-lifted`, a 1.5px `accent` edge) and a dashed slot shows where it will land.

## The launcher opens from where you clicked

**Now:** a large centred panel that stays tall when there are few results.

**Draft:** the `Launcher` drops from the `+` in the command bar, sized to its results, with a keyboard footer and a highlight that slides between rows.

## Widgets read at a glance

- Clock: tabular figures; a narrow tile stacks the place under the time rather than cutting it to one letter.
- Reminders: ticking one fills the circle, draws the tick and folds the row away after a moment, so a slip can be undone.
- Notes: an empty note says “Type anything. It stays here.” instead of showing nothing.
- Permission and empty states share one `EmptyState` layout with a single `accent` button.

## Small things

- Section labels go from 45% to 50% white so they pass 4.5:1.
- Every control gets a visible `focus` ring.
- Leaving is faster than arriving (`duration-leave` 90ms against `duration-fade` 140ms).
