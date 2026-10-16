# ontop

A macOS menu bar utility that keeps any window visible above all others. Pick a window from
the menu, or press the hotkey while it is frontmost, and it stays on top until you unpin it.

macOS gives no public way to raise another app's window level, so ontop mirrors the pinned
window into a floating overlay while another app is in front, and gets out of the way the
moment the pinned window is frontmost. Details in the [proposal](docs/proposal.md); decisions
in the [ADRs](docs/adr/).

## Status

- M0 spike passed 2026-10-16 on macOS 26.3.1: mirror shows and hides with focus, follows
  move and resize, stays live, and a click on the mirror lands in the real window.
- M1 done: menu bar window list grouped by app, pin and unpin any window, several pins at
  once, mirror hides only while its window is the focused one in the frontmost app.
- M2 in progress: global hotkey, launch at login, permission onboarding.

Development note: log lines currently print window titles and frames in the clear
(`privacy: .public` in `Sources/ontop/Log.swift` users). Switch back to the redacting default
before calling this done.

## Build

    make app       # build, bundle and sign build/ontop.app
    make run       # build and launch
    make log       # stream the app's log
    make install   # copy to /Applications

## Requirements

- macOS 26 or later
- Xcode 26 command line tools (Swift 6)
- Permissions on first use: Screen Recording and Accessibility
