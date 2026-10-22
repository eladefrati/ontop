# Click-through

A click on the mirror brings the real window forward and delivers the whole gesture to the
real window at the same points: any button, modifier keys, click count and drags. The mirror
stays up until every button is released; then it hides and the gesture is replayed once the
real window is in front at the clicked point. A window that doesn't come forward within 1 s
gets nothing: the Mac beeps and the menu's first line says the click was not delivered.

## Sub-features

- `click-forward` the click on the mirror is forwarded (log).
- `click-activate` the pinned window's app becomes frontmost and the mirror hides.
- `click-delivered` the click reaches the real window: TextEdit's insertion point moves to the clicked line.
- `click-shift` a ⇧-click extends the selection from the insertion point.
- `click-double` a double-click selects the clicked word.
- `click-right` a right-click opens the window's context menu at the point.
- `click-drag` a drag selects the dragged lines once the button is released.

## How to get to it (user POV)

- With a pinned window's mirror showing over another app, click anywhere on the mirror, with
  any button, modifiers or click count, or drag across it.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A pinned; the cover frontmost; mirror shown. Insertion point at offset 0 (fresh document).

- **Caret before.** `probe ax-caret <TextEdit pid> ontop-verify-a.txt` gives offset 0.
- **Click.** `probe click <mirror x + 120> <mirror y + 150>`, about line 5 of the document. Its report shows the mirror was the top window at that point.
- **Forwarded.** Log `click at <private>, forwarding`; `probe front` is TextEdit; mirror alpha 0.
- **Delivered.** `probe ax-caret` offset moves to line 3 to 8 (every line has the same length, so offset ÷ line length is the line). Seen: 0 → 380, line 5.
- Before each gesture below, the cover goes in front again (`probe activate <cover pid>`) and the mirror shows.
- **Shift-click.** `probe click <x + 120> <y + 250> --flags shift`. The selection starts at the insertion point the click left and ends at least four lines below it. Seen: 380+584, lines 5 to 13.
- **Double-click.** `probe click <x + 150> <y + 150> --count 2`. The selection is one whole word on line 3 to 7. Seen: "verification", line 5.
- **Right-click.** `probe click <x + 150> <y + 200> --right`. TextEdit owns a window at layer 101 (its context menu) whose left edge is within 40 pt of the click. `probe key 53` (Escape) closes it.
- **Drag.** `probe drag <x + 40> <y + 150> <x + 300> <y + 250>`. The selection starts on the first click's line and ends at least four lines below it. Seen: lines 5 to 13.

## Gotchas

- TextEdit does not support `AXInsertionPointLineNumber` (returns NSNotFound); compute the line from the offset.
- Click only at points inside the mirror's bounds, never at guessed coordinates; the click goes to whatever is on top.
- A double-click is forwarded as one click: by the second click the mirror has hidden, so the second click reaches TextEdit directly and the window server counts it as the second of a double-click. The log shows one `forwarding` line for it.
- A replayed copy of the mirror's own event lands on the mirror again (seen: a run of `forwarding` lines and no click in TextEdit), so ontop replays new events built from the recorded ones.
- A drag takes effect only on release: nothing is replayed while the button is held.
- The 1 s give-up is not driven here: it needs a target app that can't come forward. It was proven once by stopping the cover's process (SIGSTOP) with the cover pinned and clicking its mirror: `click dropped` in the log, the menu's first line "Could not click in …", no click in target A.
- Keyboard input and scrolling are not forwarded by design (README); don't test them as failures.
