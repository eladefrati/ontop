# ontop

What ontop is for and how it behaves. Kept current: a change here comes with the
[ADR](adr/README.md) that decides it.

## Overview

ontop is a macOS menu bar utility that keeps a chosen window visible above all other windows
until the user unpins it. Any app's window can be pinned, from the menu or with a global
keyboard shortcut while the window is frontmost.

macOS offers no public way to raise another process's window level. ontop therefore mirrors
the pinned window: while another app is in front, it captures the window with ScreenCaptureKit
and draws the frames in a floating window of its own, placed exactly over the original. While
the pinned window is itself frontmost the mirror is hidden and the user works in the real
window ([ADR-0001](adr/0001-mirror-overlay.md)).

## Goals

- Pin and unpin any on-screen window of any app, several at once.
- One global shortcut that toggles the pin on the frontmost window. Default chord
  Ctrl+Option+P; the user can change it.
- The pinned window stays visible on its own desktop (Space) or, with Follow Across Desktops,
  on every desktop and over full-screen apps
  ([ADR-0003](adr/0003-mirrors-stay-on-their-desktop.md)).
- A click on the mirror takes the user to the real window with that click.
- Works on stock macOS 26 with public, undeprecated APIs only.

## Non-goals

- Changing the real window level. That requires private APIs and disabling SIP.
- Keyboard input and scrolling into the mirror. Typing goes to the real window after a click.
- Persisting pins across launches.
- Notarized distribution. The source is public; a built copy is signed for the Mac that
  built it ([ADR-0002](adr/0002-build-and-packaging.md)). No App Store.

## Design

### Pinning

A pin is tied to one window, identified by its CoreGraphics window ID. Pins are made from the
menu, which lists the pinnable windows on the active desktop grouped by app, or with the
shortcut on the frontmost window. Unpin from the menu, the shortcut, or "Unpin All". Closing
or minimizing a pinned window unpins it; the app quitting unpins all of its windows. Two
toggles in a row, however close, leave the window as it was.

When a window cannot be pinned, a pin ends because its capture failed, or a click on a mirror
is not delivered, ontop beeps and the first line of its menu gives the reason until the next
pin or unpin.

### Mirror lifecycle

Each pin's mirror is in one of two states.

- **Hidden**: the pinned window is what the user sees: its app is frontmost and the window,
  or a sheet on it, is that app's focused window. Also hidden while the mirror's desktop is
  not the active one. The capture stream is stopped.
- **Shown**: otherwise. The mirror is placed at the pinned window's current frame and the
  stream runs; the mirror becomes visible with the first frame.

Transitions come from `NSWorkspace` app activation and active-desktop notifications and from
Accessibility observers on the pinned window: focused window changed, moved, resized,
minimized, destroyed. On move and resize the mirror follows, reading the frame from the
window's Accessibility position and size attributes.

A stream that fails to start, or stops, is started again after 0.5, 1 and 1.5 s. The fourth
failure in a row ends the pin.

### Interaction

The first mouse-down on the mirror raises the window through its Accessibility raise action
and activates the owning app. ontop records the gesture until every button is up: each down,
drag and up, with its button, location and modifier keys. It then replays the gesture with
new `CGEvent`s once the window's app is frontmost and owns the top window at the point of the
first press, which is the pinned window or its sheet. If that does not happen within 1 s the
gesture is dropped. Nothing is posted while a button is down, so a drag takes effect on
release. Scroll events are not forwarded
([ADR-0006](adr/0006-click-forwarding.md)).

### Mirror window

A borderless `NSWindow` at floating level that never takes focus. By default it lives on its
window's desktop; with Follow Across Desktops its collection behavior joins all Spaces and is
auxiliary to full-screen apps. It stays ordered in while hidden, transparent and ignoring
clicks, so it keeps its desktop (ADR-0003). It keeps the default sharing type, so
screenshots, recordings and screen sharing show mirrors as the screen does
([ADR-0004](adr/0004-mirrors-are-visible-to-screen-capture.md)). The content view's layer
takes each captured frame's `IOSurface` directly, with no copy. The stream leaves out the
window's shadow, and the mirror has none.

### Windows and capture

The menu's window list comes from the window server (`CGWindowListCopyWindowInfo`): on-screen
windows of other apps at layer 0, with a title, that their app allows to be captured, and
that match one of their app's standard Accessibility windows by frame, the title breaking
ties. At pin time ontop finds the window among `SCShareableContent`'s on-screen windows.
Capture uses `SCContentFilter(desktopIndependentWindow:)` with a stream configuration at best
resolution, cursor hidden, global clip ignored, child windows included, 60 frames per second
maximum and a queue depth of 3. The output size tracks the mirror's pixel size and is updated
on resize and when the display's scale factor changes.

### Menu bar

A status item with a template icon and no Dock icon: a pin, filled while a window is pinned,
slashed while a permission is missing. The menu shows the reason for the last failure, if
any, then "Pin Frontmost Window" with the shortcut, the pinnable windows grouped by app with
check marks on the pinned ones, "Unpin All", "Launch at Login", "Follow Across Desktops",
"Change Shortcut", the version, and Quit.

### Permissions

Screen Recording is needed for the window list and the capture. Accessibility is needed for
raising, frame tracking and click re-posting. The menu bar item and Quit exist from launch.
ontop asks macOS for each missing permission once per launch, Accessibility first, and shows
no dialog of its own: the menu says which permission is missing and why, and opens the
relevant Privacy & Security pane. ontop sees an Accessibility grant within a second. A Screen
Recording grant takes a restart, through macOS's Quit & Reopen or the menu's "Relaunch ontop"
([ADR-0005](adr/0005-onboarding.md)).

Since macOS 15, the system asks the user to re-confirm Screen Recording monthly. This design
accepts that. The alternative, the system content picker, needs no permission but hides the
window list from the app, which makes a shortcut on the frontmost window impossible. It may be
added later as an opt-in mode.

### Verification

The APIs above were checked against the macOS 26 SDK headers shipped with Xcode 26.6 and
compiled with warnings as errors for the macOS 26.0 target. None is deprecated. The monthly
Screen Recording prompt is from developer reports, not Apple documentation. Unit tests cover
the pure decisions behind pins, the menu and the shortcut; the behaviour that needs a
permission is proven in the running app with `.claude/skills/verify-ontop` (ADR-0002).

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

## Risks and limits

- **Mirror latency.** About one frame at 60 fps. Mitigation: the mirror is only shown when
  the user is working elsewhere; when they use the window, it is the real one.
- **Permission grants reset on rebuild.** Mitigation: sign with an Apple Development
  certificate (ADR-0002).
- **Windows that refuse capture** cannot be pinned. Accepted.
- **A pinned window moved to another desktop** in Mission Control leaves its mirror behind;
  unpin and pin again there (ADR-0003).
- **A sheet wider than its window** is scaled into the mirror with the window, so a click on
  the sheet in the mirror lands elsewhere on the real sheet (ADR-0006).
- **A shortcut another app also uses** fires in both apps; ontop cannot tell.

## Stack

Swift 6 and AppKit, no third-party dependencies. SwiftPM executable target with a Swift
Testing target; a Makefile assembles and signs the `.app` bundle and installs it to
Applications (ADR-0002). Layout: `Sources/ontop/`, `Tests/ontopTests/`, `tools/`, `docs/`.
