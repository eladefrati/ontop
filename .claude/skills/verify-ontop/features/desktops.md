# Desktops

A mirror belongs to the desktop (Space) its window was pinned on and appears only there.
"Follow Across Desktops" puts every mirror on every desktop; turning it off returns each
mirror to its own desktop (ADR-0003).

## Sub-features

- `desk-stay` with Follow off, a mirror is on its window's desktop only and off screen elsewhere.
- `desk-second` a window pinned on another desktop gets a mirror there.
- `desk-follow-on` Follow on: every mirror is on every desktop and shows away from home.
- `desk-follow-off` Follow off again: each mirror back on its own desktop.
- `desk-report` every step reports each mirror's desktop, alpha and on-screen flag.

## How to get to it (user POV)

- Pin a window, switch desktops with Ctrl+Left/Right (or a trackpad swipe).
- Menu: Follow Across Desktops (checked when on).

## Driving it with verify.py and probe

Preconditions:

- Baseline; at least two desktops; Follow off (the journey turns it off through the menu if needed; cleanup restores the starting value).

- **Pin A at home.** Raise A, `probe hotkey`, raise the cover. Report: mirror A on [home].
- **Away.** `probe space right` (left from the last desktop). Mirror A on [home], off screen.
- **Pin B away.** Open `ontop-verify-b.txt` (it opens on the active desktop), raise it, `probe hotkey`. Mirror B on [away].
- **Home.** `probe space left`. A shown; B off screen. Capture A.
- **Follow on.** `probe menu click <pid> "Follow Across Desktops"`; it shows checked. Both mirrors report every desktop. Away: A on screen and shown (B is the focused TextEdit window, A is not). Capture A there.
- **Follow off, from away.** Choose it again. Expected: A on [home], B on [away].
- **Reports.** The driver prints a line per step, e.g. `follow off, away: active desktop 4; mirror 395079 on [3] (alpha 0, onscreen False)`, and records it in `steps.jsonl` as `mirror desktops`.

## Gotchas

- 2026-10-21, four runs: turning Follow off while on another desktop moves every mirror to the active desktop (A reported on [4], not its home [3]); back home, A is off screen and its window has no mirror there. The check "after Follow off, mirror A is back on the home desktop only" fails; that is the app's behaviour, not the journey's. Inference: removing `.canJoinAllSpaces` leaves a window on the current Space; the app does not re-order it onto its window's desktop.
- Desktops are numbered 1.. in Mission Control order on the main display; the probe reads them with private SkyLight calls (verification only).
- Raising a window on another desktop makes macOS switch to that desktop. The journey switches first and raises only windows on the active desktop.
- A sticky (following) window's space list comes back in varying order; compare as sets.
