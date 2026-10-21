# Double press

Pressing the hotkey twice quickly on an unpinned window is a pin and an unpin: the window
must end unpinned, with no mirror left behind.

## Sub-features

- `double-quick` two presses 40, 80 and 150 ms apart (a person's quick double press) leave the window unpinned.
- `double-stress` two presses 0 ms apart (faster than a person) do the same; reported as `double-press-stress`.

## How to get to it (user POV)

- With the window in front, press Ctrl+Option+P twice in quick succession.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A unpinned and frontmost; Unpin All before each gap.

- **Press twice.** `probe hotkey --count 2 --gap-ms <gap>`, then wait 2 s.
- **End state.** The menu item is unchecked; ontop has no layer-3 window on screen; the log has as many `unpinned <id>` as `pinned … (<id>)` lines since the press.
- **Orphans.** After Unpin All, any mirror still on screen is an orphan the app no longer tracks: a failure, and the run relaunches ontop so the next gap starts clean.

## Gotchas

- 2026-10-21, four isolated runs: 40, 80 and 150 ms passed every time. 0 ms failed every time: three times two `pinned` lines and an orphan mirror that survives Unpin All, once one `pinned` and no second line. Inference from the code, not observed directly: both presses start `pin()` before either finishes its ScreenCaptureKit round trip, so `toggle` sees "not pinned" twice. The second shape can't be told apart from a lost synthetic key event: the app logs no line per press.
- The count of log lines is per ontop pid; after a relaunch, counting starts again.
