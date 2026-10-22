# Sheet click

A pinned window can show a sheet (Save As, Page Setup). While the window is in front with its
sheet, the mirror stays hidden, as for the window alone. While another app is in front, the
mirror shows the window with its sheet, and a click on the mirror reaches the sheet: a click on
the mirror's Cancel button presses the real sheet's Cancel.

## Sub-features

- `sheet-hidden` the mirror is hidden while the target and its sheet are in front.
- `sheet-click` a click on the mirror over the sheet presses the sheet's button, for the
  out-of-process Save As panel and the in-process Page Setup sheet; reported as
  `sheet-click save-as` and `sheet-click page-setup`.

## How to get to it (user POV)

- Pin a window, open a sheet on it (File > Save As, File > Page Setup), switch to another app,
  and click a button of the sheet on the mirror.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A grown to 960×640 at (160, 140) so each sheet fits inside it; target A
  pinned and frontmost; Unpin All before each sheet.

- **Open the sheet.** `probe key 1 --flags cmd,shift,opt` (Save As) or `probe key 35 --flags cmd,shift`
  (Page Setup) with target A in front; `probe ax-sheet <TextEdit pid> ontop-verify-a.txt` lists
  the sheet and its buttons.
- **Hidden.** One second later the mirror has alpha 0.
- **Shown.** `probe activate <cover pid>`: the mirror has alpha 1 and a capture with content.
- **Click.** `probe click` at the centre of the sheet's Cancel button from `ax-sheet`. Its
  report shows the mirror was the top window at that point.
- **Delivered.** `ax-sheet` reports no sheet within 3 s, the log has no `click dropped` line,
  and TextEdit is frontmost.
- Cleanup: a sheet left open is closed with Escape; the target goes back to 640×420.

## Gotchas

- Before the fix, 2026-10-22: with the target in front, TextEdit's focused window is the
  `AXSheet`, a child of the target, so ontop took the window as not in front and kept the
  mirror over it; and delivery waited for the target's own window id at the point, while the
  mirror, then the sheet's own window, was there. Every click was dropped (`click dropped`
  after 1 s, the sheet stayed open).
- A sheet wider than its window is scaled into the mirror with the window (seen: the Save As
  sheet, 880 pt on a 640 pt window, at 73 %), so the mirror's points no longer match the real
  ones and a click lands elsewhere on the sheet. Not fixed; the journey sizes the target so
  both sheets fit.
- The Save As sheet belongs to the out-of-process save panel service, but its window is
  listed under TextEdit's pid, and its buttons are reachable through Accessibility.
