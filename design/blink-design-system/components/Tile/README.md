# Tile

One thing you check: a page, a widget or a file, in liquid glass.

- Glass as the Principles describe it, `shadow-tile`, `radius-tile`. Widgets sit on the glass; pages sit `web-inset` inside it.
- A page tile has a title strip in its glass: a small square in `cool` with the site's initial, then the site in `ink-2`. It is always there, so you know which page you are looking at, and it never covers the page.
- Under a resting pointer, after `hover-delay`, the strip shows the page's tools on the right: back, forward, reload (its ring shows the time to the next automatic refresh) and more. They leave in `duration-leave`.
- Widgets show no strip and no hover name: their own first row says what they are (“Recent”, the calendar's date, the reminders filter). Their menu is on right-click.
- While a page loads, a 2px `accent` line runs along the top of the page; the new page crossfades in `duration-fade`.
- The consumer provides the content and, for pages, the site and its tools.
