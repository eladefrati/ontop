---
name: verify-ontop
description: Verify ontop, the macOS 26 menu bar app in this repo that pins a window above all others through a ScreenCaptureKit mirror, by driving the real signed build on this Mac (hotkey, status menu, clicks, desktop switches) and capturing screencapture -l images plus the app's log. Use when a change to ontop needs proof in the running app, before calling an ontop fix done, or when asked to test pinning, unpinning, the mirror, click-through or Follow Across Desktops.
---

# Verify ontop on this Mac

ontop is an `LSUIElement` app: no Dock icon, no main window. A user touches three things: the
global hotkey (Ctrl+Option+P), the pin icon in the menu bar, and the mirror window that
floats over a pinned window while another app is in front. This skill drives all three the
way a user would, with `scripts/probe` (CGEvent keys and clicks, Accessibility for the
menu) and `scripts/verify.py` (the journeys), on throwaway windows only.

Run everything from the repo root, `~/dev/ontop`.

## Rules

- **Throwaway windows only.** Targets are new TextEdit documents the run writes into its
  own folder (`ontop-verify-a.txt`, `ontop-verify-b.txt`); "another app in front" is the
  probe's own cover window ("ontop-verify cover", an orange window). Never pin, click, close
  or raise a window the run did not open. The user's own TextEdit documents stay untouched.
- **Never reset or edit TCC.** The terminal (iTerm) needs Accessibility and Screen
  Recording; the build signed with the Apple Development certificate already holds the
  app's grants. If either is missing, the doctor says so: ask the user to turn it on.
- **One ontop at a time.** The test build and the installed `/Applications/ontop.app` share
  the bundle id, the defaults and the hotkey. A run quits the installed instance through
  its own menu only when it holds no pins, and reopens it in cleanup (agreed with the user
  2026-10-21). With pins, the doctor refuses: the user is using it.
- **Kill only what the run started**, by the pid recorded in the run's `state.json`.
- The run switches desktops (Spaces) with Ctrl+Left/Right and toggles Follow Across
  Desktops; cleanup returns to the starting desktop and restores the setting.
- The screen is shared with the user. A run takes about 90 seconds and moves windows and
  desktops; it does not need the user's hands.

## Doctor

Read-only. Run it first, and again whenever something looks off:

```sh
.claude/skills/verify-ontop/scripts/verify.py doctor
```

It checks macOS 26, the terminal's Accessibility and Screen Recording (through the probe),
the build's Apple Development signature, any running ontop (test build left over, or an
installed one with pins), a custom shortcut (the probe presses only the default), and that
a second desktop exists. It prints `READY` or `NOT READY` with one line per problem. Exit
status 1 when not ready.

## Launch and teardown

`verify.py run` does it all; this is what it runs, for reading failures:

1. Quits an installed ontop that has no pins (menu "Quit ontop").
2. `make app` (builds, bundles, signs `build/ontop.app`).
3. Starts `log stream --level info --style compact --predicate 'subsystem == "io.github.eladefrati.ontop"'` into the run's `ontop.log`.
4. `open build/ontop.app`. **Ready** means the new pid logged `hotkey registered`. No
   such line within 10 s usually means onboarding is waiting for a permission this build
   lacks (icon `pin.slash`, the menu reads "ontop needs … access"): the run aborts and
   says so. Don't grant it; ask the user.
5. Opens target A in TextEdit at (160, 140, 640×420) and starts the cover at (100, 100, 900×560).

Teardown (cleanup) unpins everything, restores Follow Across Desktops, quits the test build
through its menu (SIGTERM to its pid if the menu fails), closes the cover and the target
documents, quits TextEdit only if the run launched it, returns to the starting desktop,
stops the log stream, and reopens the installed ontop if the run quit it.

```sh
.claude/skills/verify-ontop/scripts/verify.py run                      # every feature
.claude/skills/verify-ontop/scripts/verify.py run pin-hotkey desktops  # some features
.claude/skills/verify-ontop/scripts/verify.py run --keep click-through # leave it all up to inspect
.claude/skills/verify-ontop/scripts/verify.py cleanup build/verify/runs/<run>   # after --keep or a crash
```

Exit status 0 all passed, 1 some check failed, 2 the run could not start or aborted.

## Drive

`verify.py` is the driver; `features/` says what each journey proves and why. For a case
the journeys don't cover, use the probe directly (it prints JSON; compiles itself on first
use into `build/verify/bin/`):

```sh
P=.claude/skills/verify-ontop/scripts/probe
$P trusted                          # {"accessibility":…, "screenRecording":…} for this terminal
$P windows --pid <ontop pid> --all  # ontop's windows; layer 3 = mirrors. id, alpha, onscreen, bounds, desktops
$P windows --owner TextEdit         # find a target's CGWindowID (names need Screen Recording)
$P hotkey [--count 2 --gap-ms 80]   # Ctrl+Option+P through the HID event tap
$P menu list <ontop pid>            # open the status menu, list items (title, enabled, checked, section), close
$P menu click <ontop pid> "<item>" [--section TextEdit]   # choose an item; window items sit under their app
$P front                            # frontmost app pid
$P activate <pid>                   # bring an app to the front (Accessibility AXFrontmost)
$P ax-windows <pid>                 # an app's windows: title, frame, focused
$P ax-place <pid> "<title>" x y w h # move and size a window
$P ax-raise <pid> "<title>"         # that window to the front of its app, the app to the front
$P ax-close <pid> "<title>"         # press its close button
$P ax-caret <pid> "<title>"         # insertion point offset in the window's text area
$P click x y                        # left click at global top-left coordinates; reports what was on top
$P space left|right                 # Ctrl+Arrow desktop switch, waits for it
$P desktops                         # active desktop and every desktop's space id
$P cover x y w h [--title T]        # throwaway frontmost app window; blocks, kill its pid
$P opaque <png>                     # share of non-transparent pixels in a capture
$P quit <pid>                       # polite quit, as Cmd+Q
```

Handles: menu items by their exact titles (`Pin Frontmost Window`, `Unpin All`,
`Follow Across Desktops`, `Quit ontop`, a window's title under its app's header); windows by
CGWindowID; mirrors as ontop-owned windows at layer 3. Never click by guessed coordinates:
compute the point from a mirror's `bounds`, and `probe click` reports which window was on top.

## Evidence

Every run writes `build/verify/runs/<YYYY-MM-DDTHHMMSS>/`, which cleanup never removes:

- `summary.md`: PASS/FAIL per check with the measured detail.
- `steps.jsonl`: each action in order with the probe's JSON (window states, menu
  contents, caret offsets, desktop reports), so the state before and after every action is on record.
- `ontop.log`: the app's log for the run. Strings are `<private>` (Log.swift: the
  unified-logging default); integers such as window ids are readable, so `pinned <private> (395235)` and `unpinned 395235` identify the window.
- `NNN-<feature>-<label>.png`: `screencapture -l <window id> -o -x` of the mirror (or the cover), named by step number.

Proof standards: drive the user path (hotkey, menu, click), never PinManager or defaults;
pair each action with the resulting state (mirror alpha and on-screen flag from the window
server, menu check marks, frontmost app, caret, log line); a visible mirror proof needs a
capture with content (`opaque` > 0.9), not only alpha 1. `make clean` deletes
`build/`, evidence included: copy a run out first if it must be kept.

## Cleanup

`verify.py run` cleans up in a `finally`, so an exception still tears down. After
`--keep`, an abort, or a killed run, `verify.py cleanup <run dir>` reads `state.json` and
does the same. Then run the doctor: it flags a leftover test build.

## Known limits

- Desktop reporting uses private SkyLight calls (`CGSCopySpacesForWindows`,
  `CGSCopyManagedDisplaySpaces`) in the probe only. ADR-0001 keeps them out of the app.
- Desktop switching needs Mission Control's "Move left/right a space" shortcuts
  (Ctrl+Left/Right) enabled, as they are on this Mac.
- One display tested. Mirrors over full-screen apps are not exercised.
- Not covered yet: Change Shortcut, Launch at Login (it changes login items), moving or
  resizing a pinned window, closing or minimizing it (auto-unpin), stream restart.
