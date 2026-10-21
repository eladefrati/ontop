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
- **Both presses arrived.** The log has two `hotkey pressed` lines since the press, so a lost synthetic key event is not mistaken for a lost pin.
- **End state.** The menu item is unchecked; ontop has no layer-3 window on screen; the log has as many `unpinned <id>` as `pinned … (<id>)` lines since the press.
- **Orphans.** After Unpin All, any mirror still on screen is an orphan the app no longer tracks: a failure, and the run relaunches ontop so the next gap starts clean.

## Gotchas

- Before the fix, 2026-10-21: 40, 80 and 150 ms passed every time; 0 ms failed every time, either two `pinned` lines and an orphan mirror that survived Unpin All, or one `pinned` line and no unpin. Both presses reached `toggle` before either finished its ScreenCaptureKit round trip, so both saw "not pinned". Now a toggle claims the window's slot at the press, the second press cancels it, and the first press's lookup builds nothing: a 0 ms double press logs `pin cancelled (<id>)` and no `pinned` line.
- The count of log lines is per ontop pid; after a relaunch, counting starts again.
