# ontop

A macOS menu bar utility that keeps any window visible above all others. Pick a window from
the menu, or press the hotkey while it is frontmost, and it stays on top until you unpin it.

macOS gives no public way to raise another app's window level, so ontop mirrors the pinned
window into a floating overlay while another app is in front, and gets out of the way the
moment the pinned window is frontmost. Details in the [proposal](docs/proposal.md); decisions
in the [ADRs](docs/adr/).

## Install

Requires macOS 26 and Xcode 26 or its command line tools.

    git clone https://github.com/eladefrati/ontop.git
    cd ontop
    make install

Then open ontop from Applications and grant Accessibility and Screen Recording when asked.
It runs as a pin icon in the menu bar; there is no Dock icon.

## Use

- Click the pin in the menu bar and pick a window, or press Ctrl+Option+P while the window
  you want is in front. Pick or press again to unpin. "Unpin All" clears everything.
- The pinned window is the real window while you work in it. When another app comes to the
  front, a live mirror of the pinned window appears in its place, above everything. Click
  the mirror and you are back in the real window, with that click delivered.
- A pinned window stays on the desktop it was pinned on. Turn on "Follow Across Desktops"
  to see pinned windows on every desktop and over full-screen apps.
- "Change Shortcut" records a new key combination; "Launch at Login" does what it says.
- Pins are not remembered across launches.

Limits that follow from the design: the mirror does not take keyboard input, it lags the
real window by about a frame, and windows an app marks as not capturable cannot be pinned.
macOS asks you to re-confirm Screen Recording access about once a month.

## Build

    make app       # build, bundle and sign build/ontop.app
    make run       # build and launch
    make log       # stream the app's log
    make install   # copy to /Applications

Signing: the Makefile signs with the first "Apple Development" certificate in your keychain
and falls back to an ad-hoc signature with a warning. Both run fine on the Mac that built
them. With an ad-hoc signature macOS treats every rebuild as a new app, so the two
permissions have to be granted again after each build. A free Apple Development certificate
avoids that: in Xcode, Settings > Accounts, add your Apple ID, select the Personal Team,
Manage Certificates, then + > Apple Development. No paid program needed.

Copies of the built app do not pass Gatekeeper on other Macs, since nothing here is
notarized. After the first blocked launch the recipient has to scroll to the Security
section of System Settings > Privacy & Security and click "Open Anyway", once.

## License

MIT, see [LICENSE](LICENSE).

Built with Claude Code.
