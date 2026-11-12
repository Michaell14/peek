# Launcher

Adding a website, a widget or a file: a field and a list, opened from Add in the `CommandBar`.

- Opens from the `+` (its transform origin is the button), scaling from 0.96 and dropping 6px in `duration-move`; rows arrive 12ms apart. It is only as tall as its results.
- `tile-raised`, `stroke` hairline, `shadow-panel`, `radius-panel`, 520px wide.
- The field uses `search` type with an `accent` caret. Rows are `size-row` high: a 28px tinted square with the symbol (`accent` for widgets and files, `cool` for websites), `row-title` and `row-detail`, and `↩` on the selected row.
- The highlight slides between rows with `spring-select`. `↑` `↓` choose, `↩` adds, `esc` closes.
- Typing filters the list; an address or a search becomes the first row.
