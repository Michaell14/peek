# MessagesWidget

Your recent conversations, read and answered without opening Messages.

- The list: a `size-avatar` circle of initials (a group gets its own), the name in `row-title` and the last message in `row-detail`, the time on the right. Unread rows set the name at 600 and the message in `ink`, with an `accent` dot; the head counts what is unread.
- Click a conversation and its thread slides in (`duration-move`): received bubbles in `bubble-in`, sent ones in `accent` with `on-accent` text, `radius-bubble` with the sender's corner tightened. New bubbles rise 6px into place.
- Reply in the field at the bottom; Return sends. The send button is dim until there is something to send. “Delivered” follows your last message in `ink-2`.
- Avatars are initials, never photos, so the board stays calm.
- On the Mac this needs Full Disk Access to read recent conversations from the Messages app's own data, and sends through the Messages app. Ask for both only when the widget is added, and say why.
