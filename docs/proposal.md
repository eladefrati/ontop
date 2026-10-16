# ontop design

Design document. Status: accepted 2026-10-16. Changes after acceptance go to
[ADRs](adr/), not to this file.

## Overview

ontop is a macOS menu bar utility that keeps a chosen window visible above all other windows
until the user unpins it. Any app's window can be pinned, from the menu or with a global
keyboard shortcut while the window is frontmost.

macOS offers no public way to raise another process's window level. ontop therefore mirrors
the pinned window: while another app is in front, it captures the window with ScreenCaptureKit
and draws the frames in a floating window of its own, placed exactly over the original. While
the pinned window is itself frontmost the mirror is hidden and the user works in the real
window.

## Goals

- Pin and unpin any on-screen window of any app, several at once.
- One global shortcut that toggles the pin on the frontmost window. Default chord Ctrl+Option+P.
- The pinned window stays visible across Spaces and over full-screen apps.
- A click on the mirror takes the user to the real window with that click.
- Works on stock macOS 26 with public, undeprecated APIs only.

## Non-goals

- Changing the real window level. That requires private APIs and disabling SIP.
- Keyboard input into the mirror. Typing goes to the real window after a click.
- Persisting pins across launches, in the first version.
- Distribution outside this machine. No notarization, no App Store.

## Design

### Pinning

A pin is tied to one window, identified by its CoreGraphics window ID. Pins are made from the
menu, which lists on-screen windows grouped by app, or with the shortcut on the frontmost
window. Unpin from the menu, the shortcut, or "Unpin all". Closing or minimizing a pinned
window unpins it; the app quitting unpins all of its windows.

### Mirror lifecycle

Each pin is in one of two states.

- **Hidden**: the pinned window is frontmost. No mirror is shown and the capture stream is
  stopped.
- **Shown**: another window is in front. The mirror is shown at the pinned window's current
  frame and the stream runs.

Transitions come from `NSWorkspace` app activation notifications and from Accessibility
observers on the pinned window: focused window changed, moved, resized, minimized,
destroyed. On move and resize the mirror follows, reading the frame from the window's
Accessibility position and size attributes.

### Interaction

A mouse-down on the mirror activates the owning app, raises the window through its
Accessibility raise action, hides the mirror, and re-posts the mouse-down and mouse-up at the
same screen point with `CGEvent`, so the click lands in the real window. The re-posting step
is unverified and is the subject of the M0 spike; the fallback is activate-and-raise only.
Scroll events are not forwarded in the first version.

### Mirror window

A borderless `NSWindow` at floating level with collection behavior set to join all Spaces and
to be auxiliary to full-screen apps. Its sharing type is set to none so ontop never captures
its own mirrors. The content view's layer takes each captured frame's `IOSurface` directly,
with no copy. The window's own shadow is captured with the stream, so the mirror looks like
the window.

### Capture

Window enumeration uses `SCShareableContent`, excluding desktop windows and keeping on-screen
windows only. Only windows at layer 0 with a title are offered. Capture uses
`SCContentFilter(desktopIndependentWindow:)` with a stream configuration at best resolution,
cursor hidden, global clip ignored, child windows included, 60 frames per second maximum and
a queue depth of 3. The output size tracks the window's pixel size and is updated on resize.

### Menu bar

A status item with a template icon and no Dock icon. The menu shows pinned windows with
checkmarks, then on-screen windows grouped by app, then "Pin frontmost window" with the
shortcut, "Unpin all", "Launch at login", "Settings" for the chord, and Quit.

### Permissions

Screen Recording is needed for the window list and the capture. Accessibility is needed for
raising, frame tracking and click re-posting. When a permission is missing ontop shows one
alert that explains why and opens the relevant Privacy & Security pane. It never repeats a
denied prompt in a loop.

Since macOS 15, the system asks the user to re-confirm Screen Recording monthly. This design
accepts that. The alternative, the system content picker, needs no permission but hides the
window list from the app, which makes a shortcut on the frontmost window impossible. It may be
added later as an opt-in mode.

### Verification

The APIs above were checked against the macOS 26 SDK headers shipped with Xcode 26.6 and
compiled with warnings as errors for the macOS 26.0 target. None is deprecated. The monthly
Screen Recording prompt and the permission-free status of Carbon hotkeys on macOS 26 are from
developer reports, not Apple documentation. Click re-posting is untested.

## Alternatives considered

- **Private window-level calls through a scripting addition**, as yabai does. Real pinning,
  but needs SIP partially disabled. Rejected.
- **System content picker only.** No permissions and no monthly prompt, but no shortcut on
  the frontmost window. Deferred as a possible mode.
- **iTerm2's floating hotkey window.** Solves one app and only for a dedicated window, not
  existing ones.
- **An existing open source tool.** Topit implements the same idea but was last updated in
  2024. Rejected in favour of a maintained implementation built from current SDK
  documentation, without reference to its code.

## Risks

- **Click re-posting fails or misfires.** Mitigation: M0 tests it first; fallback is a plain
  activate-and-raise, costing the user one extra click.
- **Mirror latency feels wrong.** About one frame at 60 fps. Mitigation: the mirror is only
  shown when the user is working elsewhere; when they use the window, it is the real one.
- **Permission grants reset on rebuild.** Mitigation: sign with an Apple Development
  certificate ([ADR-0002](adr/0002-build-and-packaging.md)).
- **Windows that refuse capture** cannot be pinned. Accepted.

## Milestones

- **M0, spike.** One hard-coded iTerm2 window. Mirror shows and hides with focus; click
  re-posting tested. The one result that could change the interaction design.
- **M1.** Menu bar with window list, pin and unpin, follow move and resize, auto-unpin.
- **M2.** Shortcut with changeable chord, launch at login, permission onboarding.
- **M3.** Multi-display, scale factor changes, stream error recovery.

## Stack

Swift 6 and AppKit, no third-party dependencies. SwiftPM executable target; a Makefile
assembles and signs the `.app` bundle and installs it to Applications
([ADR-0002](adr/0002-build-and-packaging.md)). Layout: `Sources/ontop/`, `docs/`.
