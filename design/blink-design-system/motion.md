# Motion

Motion in Blink confirms what just happened and then gets out of the way. Every moment below names its tokens; the **Hold and tap** page plays the first four.

| Moment | What moves | Timing |
|---|---|---|
| Arrive (key held) | `scrim` and tiles fade in; each tile also scales from 0.985 to 1 | `duration-fade`, `ease-arrive`; tiles start `stagger` apart, nearest the pointer first, six at most |
| Leave (key released) | Everything fades out at once, no scale | `duration-leave`, `ease-leave` |
| Pin (key tapped) | Tiles stay; the `CommandBar` drops 6px into place and fades in, after the tiles have settled | `duration-move`, `ease-arrive`, starting `duration-fade` after Arrive |
| Unpin (tap again, esc) | Same as Leave; the bar goes with the tiles | `duration-leave`, `ease-leave` |
| Tile head | A tile's head and tools fade in under a resting pointer and out when it leaves | in `duration-fade` after `hover-delay`; out `duration-leave` |
| Layout mode | The selected segment slides; tiles glide to their new frames | segment `spring-select`; tiles `spring-reflow` |
| Arrange on | Tiles dim to 55%, handles and remove buttons fade in; content keeps its place | `duration-fade` |
| Lift (drag starts) | The tile scales to 1.02, gains `shadow-lifted` and a 1.5px `accent` edge | `duration-move`, `ease-arrive` |
| Reflow | Other tiles make room; a dashed slot shows where the tile will land | `spring-reflow` |
| Snap | A 1px `accent` guide flashes along the aligned edge | in at once, out `duration-move` |
| Launcher | Opens from the `+` button: scales from 0.96 and drops 6px; rows arrive 12ms apart; the highlight slides between rows | panel `duration-move`; highlight `spring-select` |
| Add a tile | The new tile grows from the launcher row into its slot; the launcher fades | `spring-reflow` |
| Open a conversation | The list slides 24px left and fades as the thread slides in from the right | `duration-move`, `ease-arrive`; back is the same, reversed |
| Send a message | The new bubble rises 6px and fades in; “Delivered” follows it | `duration-move`, `ease-arrive` |
| Choose a template | The picker leaves; the template's tiles arrive one by one, 70ms apart; the command bar follows | picker `duration-leave`; tiles `duration-fade` and `duration-move`, `ease-arrive` |
| Tick a reminder | The circle fills `accent`, the tick draws, the title fades to `ink-3`; the row folds away 1.2s later | fill `duration-fade`; tick `duration-move`; fold `duration-settle` |
| Refresh | A 2px `accent` line runs along the tile's top while loading; the new page crossfades in | line tracks progress; crossfade `duration-fade` |
| Press | Fills step to `control-selected` or `accent-pressed` while held | at once, release `duration-leave` |

## Rules

- Never animate anything the person is waiting on to get back to work: leaving is always `duration-leave` and never staggered.
- One thing moves at a time per tile: a tile that is reflowing does not also fade.
- Stagger at most six tiles; the rest arrive with the sixth.
- Springs are for things a person moved (a selection, a tile). Scripted entrances use curves.
- Reduce Motion: every movement becomes a crossfade of the same duration; staggers drop to zero; the tick appears without drawing.
- Nothing loops, pulses or bounces while Blink is open.
