# Click-through

A click on the mirror brings the real window forward, hides the mirror, and delivers the
click to the real window at the same point, so the user lands where they clicked.

## Sub-features

- `click-forward` the click on the mirror is forwarded (log).
- `click-activate` the pinned window's app becomes frontmost and the mirror hides.
- `click-delivered` the click reaches the real window: TextEdit's insertion point moves to the clicked line.

## How to get to it (user POV)

- With a pinned window's mirror showing over another app, click anywhere on the mirror.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A pinned; the cover frontmost; mirror shown. Insertion point at offset 0 (fresh document).

- **Caret before.** `probe ax-caret <TextEdit pid> ontop-verify-a.txt` gives offset 0.
- **Click.** `probe click <mirror x + 120> <mirror y + 150>`, about line 5 of the document. Its report shows the mirror was the top window at that point.
- **Forwarded.** Log `click at <private>, forwarding`; `probe front` is TextEdit; mirror alpha 0.
- **Delivered.** `probe ax-caret` offset moves to line 3 to 8 (every line has the same length, so offset ÷ line length is the line). Seen: 0 → 380, line 5.

## Gotchas

- TextEdit does not support `AXInsertionPointLineNumber` (returns NSNotFound); compute the line from the offset.
- Click only at points inside the mirror's bounds, never at guessed coordinates; the click goes to whatever is on top.
- Keyboard input and scrolling are not forwarded by design (README); don't test them as failures.
