# ClockWidget

The time in the places you care about.

- Each row: a `sun` (in `accent`) or `moon` (in `cool`) symbol for day or night there, the place in `row-title`, its day and offset in `row-detail`, and the time in `clock` figures with a small AM/PM.
- Rows are split by `stroke` hairlines. Figures are tabular so minutes changing never shift the row.
- In a narrow tile the place stacks under the time rather than being cut short (`.bk-clock--narrow`); never truncate a place to one letter.
