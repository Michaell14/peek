# CalendarWidget

Today's events as a timeline, or the next seven days as a list.

- Head: the day in `date` figures, the weekday in small capitals in `late` (as Calendar does) and the month in `ink-2`, and a Day/7 Days `SegmentedControl`.
- Hours are `stroke` hairlines with `ink-3` labels; events are `radius-row` blocks in `control-selected` with the calendar's own colour as a 2px left edge.
- The now line is `late`, 1.5px, with a dot at its start; the timeline scrolls to keep it in view.
