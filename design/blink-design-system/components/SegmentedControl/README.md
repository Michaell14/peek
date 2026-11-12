# SegmentedControl

A compact switch between two to four options, with a highlight that slides.

- Track `control`, thumb `control-selected`, segments `size-segment` high in `label` type; unselected `ink-2`.
- The thumb moves with `spring-select` (in CSS: `duration-move`, `ease-arrive`). Text never moves.
- The layout mode switch (`.bk-seg--mode`) is the one place selected text turns `accent`, because it says how the board behaves.
- Give options icons only where the shape explains the option (Flow, Freeform).
- The consumer provides the options and the selected value; the control reports changes.
