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
- M2 done: global shortcut (default Ctrl+Option+P, changeable from the menu), launch at
  login, permission onboarding that opens the right settings pane and relaunches.
- M3 done: stream restarts with backoff if the system stops it and unpins after repeated
  failures; the capture is re-sized when the mirror lands on a display with another scale
  factor. Multi-display geometry is by construction (one global coordinate flip) and
  untested on hardware, as is the restart path: a display sleep and wake did not stop the
  stream.

## Build

    make app       # build, bundle and sign build/ontop.app
    make run       # build and launch
    make log       # stream the app's log
    make install   # copy to /Applications

## Use

- Click the pin in the menu bar and pick a window, or press Ctrl+Option+P while the window
  you want is in front. Pick or press again to unpin. "Unpin All" clears everything.
- The pinned window is the real window while you work in it. When another app comes to the
  front, a live mirror of the pinned window appears in its place, above everything. Click
  the mirror and you are back in the real window, with that click delivered.
- "Change Shortcut" records a new key combination; "Launch at Login" does what it says.
- Pins are not remembered across launches.

Limits that follow from the design: the mirror does not take keyboard input, it lags the
real window by about a frame, and windows an app marks as not capturable cannot be pinned.
macOS asks you to re-confirm Screen Recording access about once a month.

## Requirements

- macOS 26 or later
- Xcode 26 command line tools (Swift 6)
- Permissions on first use: Screen Recording and Accessibility

## License

MIT, see [LICENSE](LICENSE).
