# SegmentedControl

A compact switch between two to four options, with a highlight that slides.

- Track `control`, thumb `control-selected`, segments `size-segment` high in `label` type; unselected `ink-2`.
- The thumb moves with `spring-select` (in CSS: `duration-move`, `ease-arrive`). Text never moves.
- Selected text stays `ink`; the thumb alone says which option is on.
- The consumer provides the options and the selected value; the control reports changes.
