# Templates

What a new board offers instead of an empty state: ready-made boards for what people check most.

- Shown on first launch, whenever the last tile is removed, and from Add → “Start from a template”.
- A heading and one line, then six cards in a grid: a map of the board (glass blocks for widgets, white blocks for pages, each with its icon), the name in `row-title` weight 600, one line on what it is for, and chips naming its tiles.
- One card is always selected (Workday first), shown by a 2px `accent` ring; the primary button names it: “Use Workday”. “Start empty” sits opposite, plain.
- Choosing builds the board in place: the picker leaves in `duration-leave`, then the tiles arrive one by one, `stagger` apart, and the command bar follows. Websites ask nothing; Calendar, Reminders and Messages ask for their permission when they first appear, not before.
- The templates: Workday, Engineering, Remote team, Markets, Study, Creator. Websites in them are suggestions people can change from each tile's `…` menu.
