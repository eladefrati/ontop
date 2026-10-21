# Launch and quit

The app starts with no Dock icon and no window: a pin appears in the menu bar, and its menu
ends with the version and "Quit ontop", which ends the process.

## Sub-features

- `launch-ready` the built app starts and registers its hotkey.
- `launch-menu` the menu bar item opens a menu with Pin Frontmost Window and Quit ontop.
- `launch-version` the menu shows the built version, `ontop <CFBundleShortVersionString>`.
- `quit-menu` Quit ontop ends the process.

## How to get to it (user POV)

- Open `build/ontop.app` (or `/Applications/ontop.app` after `make install`).
- Click the pin icon in the menu bar.
- Choose Quit ontop, or press Cmd+Q while the menu is open.

## Driving it with verify.py and probe

Preconditions:

- No ontop running (the run quits a pinless installed one first).

- **Launch.** `make app`, then `open build/ontop.app`. Ready: the new pid logs `hotkey registered: <private>` within 10 s.
- **Open the menu.** `probe menu list <pid>`. Items include `Pin Frontmost Window` and `Quit ontop`.
- **Version.** The disabled item `ontop 2026.10.20.1` matches `CFBundleShortVersionString` in `build/ontop.app/Contents/Info.plist`.
- **Quit.** `probe menu click <pid> "Quit ontop"`. The pid is gone within 5 s.
- **Relaunch.** `open build/ontop.app` again reaches ready; the other journeys run on it.

## Gotchas

- `open build/ontop.app` only activates an already running ontop with the same bundle id, including the installed one. The doctor and the run make sure none is running.
- In macOS 26 the status item's window belongs to Control Center, not ontop: `probe windows --pid <ontop>` lists no window for it. Reach the menu through Accessibility (`AXExtrasMenuBar`).
- The menu's AXMenu element outlives the menu with its old items. The probe treats the menu as open only while the status item's `AXSelected` is true; reading the stale element gave wrong check marks.
- An onboarding alert ("ontop needs … access") means the build lacks a grant. Don't click it; ask the user. Never reset TCC.
