# RemindersWidget

What is due, ready to tick off.

- A filter (`SegmentedControl`: Today, Later, All) and the count still due in `count` type, `accent`.
- Groups under a `Caption` (“Overdue”, “Today”); overdue details in `late`, always with the word (“Yesterday”).
- Ticking: the circle fills `accent` in `duration-fade`, the tick draws in `duration-move`, the title fades to `ink-3`; 1.2s later the row folds away in `duration-settle`. Ticking again before then undoes it.
- “New Reminder” at the end, in `ink-3` until focused.
