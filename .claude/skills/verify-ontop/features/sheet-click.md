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
- `sheet-fit` the mirror covers the window and a sheet wider than it, point for point.
- `sheet-corner` a click on the mirror's empty corner, beside the window and above the sheet,
  goes to the app underneath.

## How to get to it (user POV)

- Pin a window, open a sheet on it (File > Save As, File > Page Setup), switch to another app,
  and click a button of the sheet on the mirror.

## Driving it with verify.py and probe

Preconditions:

- Baseline, so both sheets are wider than target A (640 pt); target A pinned and frontmost;
  Unpin All before each sheet.

- **Open the sheet.** `probe key 1 --flags cmd,shift,opt` (Save As) or `probe key 35 --flags cmd,shift`
  (Page Setup) with target A in front; `probe ax-sheet <TextEdit pid> ontop-verify-a.txt` lists
  the sheet and its buttons.
- **Hidden.** One second later the mirror has alpha 0.
- **Shown.** `probe activate <cover pid>`: the mirror has alpha 1 and a capture with content.
- **Fit.** The mirror's bounds are the union of the window and the sheet. Seen: Save As,
  (40, 140) 880×516 for the window at (160, 140) 640×420; Page Setup, (149, 140) 663×420.
- **Corner.** Where the sheet reaches past the target's right edge, `probe click` 20 pt inside
  the sheet's right edge and 20 pt below the target's top: the mirror is the top window there,
  the log gains no `forwarding` line, and the cover stays frontmost. Seen for Save As only;
  Page Setup's sheet ends 12 pt past the target, so it has no corner to click.
- **Click.** `probe click` at the centre of the sheet's Cancel button from `ax-sheet`. Its
  report shows the mirror was the top window at that point.
- **Delivered.** `ax-sheet` reports no sheet within 3 s, the log has no `click dropped` line,
  and TextEdit is frontmost.
- Cleanup: a sheet left open is closed with Escape.

## Gotchas

- Before the fix, 2026-10-22: with the target in front, TextEdit's focused window is the
  `AXSheet`, a child of the target, so ontop took the window as not in front and kept the
  mirror over it; and delivery waited for the target's own window id at the point, while the
  mirror, then the sheet's own window, was there. Every click was dropped (`click dropped`
  after 1 s, the sheet stayed open).
- Before the fix, 2026-11-10: a sheet wider than its window was scaled into the mirror with
  the window (the Save As sheet, 880 pt on a 640 pt window, at 73 %), so a click landed
  elsewhere on the sheet, and the real Cancel button lay outside the mirror. A frame carries
  the true size, content rect ÷ content scale (640×375.27 ÷ 0.727 = 880×516), but not where
  it is on screen (its screen rect stays the window's), so the mirror takes its frame from the
  window's and its sheets' Accessibility frames, and a frame whose content size changes is
  the cue to read them again.
- A mirror that sets `ignoresMouseEvents`, even to false, takes clicks on its empty corners
  too (seen: a corner click forwarded, TextEdit raised). Never set, macOS gives it a click
  only where it shows a pixel.
- The Save As sheet belongs to the out-of-process save panel service, but its window is
  listed under TextEdit's pid, and its buttons are reachable through Accessibility.
