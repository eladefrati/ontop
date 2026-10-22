# ontop verification map

The maintained source for verifying what an ontop user can do. Read this index, then the
feature file, before driving. Every journey is implemented in `../scripts/verify.py` under
the same name; `verify.py run <feature>` drives it.

## Baseline preconditions

- `verify.py doctor` prints `READY`.
- The test build `build/ontop.app` is the only ontop running, launched by this run, and has
  logged `hotkey registered`.
- Target A, a TextEdit document `ontop-verify-a.txt` written into the run folder, sits at
  (160, 140) 640×420 on the starting desktop, unpinned.
- The cover window "ontop-verify cover" (another app, the probe) sits at (100, 100) 900×560,
  overlapping target A.
- Follow Across Desktops is off at the start of `desktops`.

## Driving conventions

- Start each journey from the baseline; each ends with Unpin All.
- Act through `scripts/probe`: hotkey through the HID event tap, menu through Accessibility,
  clicks as CGEvents at points computed from window bounds.
- Read state from the window server (`probe windows`: alpha, onscreen, desktops), the menu
  (check marks), the frontmost app, and the log. A mirror is shown when alpha 1 and on screen,
  hidden when alpha 0 (it stays ordered in to keep its desktop, ADR-0003), gone when off screen
  after an unpin.
- Never touch a window the run did not open.

## Proof and skip reporting

- Each check pairs an action with the resulting state and lands in `summary.md`,
  with the probe output in `steps.jsonl`.
- A shown mirror needs a `screencapture -l` image with content, not only alpha 1.
- Report a journey that cannot run (doctor problem, abort) with the reason; never report a
  feature verified through a different entry point than its file names.

## Feature entry contract

Each file: an H1, one paragraph of user-visible behaviour, then `Sub-features`,
`How to get to it (user POV)`, `Driving it with verify.py and probe` (starting with
`Preconditions:`), `Gotchas`.

## Features

- [Launch and quit](./launch-quit.md): the menu bar item appears, shows the version, Quit ends the app.
- [Pin with the hotkey](./pin-hotkey.md): Ctrl+Option+P pins and unpins the frontmost window.
- [Pin from the menu](./pin-menu.md): window items, Pin Frontmost Window, Unpin All.
- [Mirror visibility](./mirror-visibility.md): shown while another app is in front, hidden while the pinned window is.
- [Click-through](./click-through.md): a click, right-click, double-click, ⇧-click or drag on the mirror lands in the real window.
- [Sheet click](./sheet-click.md): with a sheet open, the mirror hides while the window is in front, and a click on the mirror reaches the sheet.
- [Double press](./double-press.md): a quick double press leaves the window unpinned.
- [Desktops](./desktops.md): mirrors stay on their desktop; Follow Across Desktops.
