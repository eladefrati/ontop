---
title: "ADR-0001: Pin by mirroring the window into a floating overlay"
status: Accepted
date: 2026-10-16
---

# ADR-0001: Mirror overlay

**Status:** Accepted. Decision 1 amended by [ADR-0003](0003-mirrors-stay-on-their-desktop.md).

## Context

The goal is to keep any window of any app above all others ([proposal](../proposal.md)).
macOS has no public API to change another process's window level. The Accessibility API can
move, resize and raise foreign windows but not set their level. Code injection is blocked by
SIP and the hardened runtime. Private SkyLight calls work only from a process injected into
Dock.app, which requires SIP to be partially disabled.

## Decision

1. ontop captures the pinned window with ScreenCaptureKit
   (`SCContentFilter(desktopIndependentWindow:)`) and draws the frames in its own borderless
   window at floating level, joined to all Spaces and allowed over full-screen apps.
2. The overlay is shown only while the pinned window is not frontmost. When it is frontmost
   the overlay hides and the stream pauses; the user works in the real window.
3. Windows are enumerated by ontop itself under the Screen Recording permission, not through
   `SCContentSharingPicker`, so a global hotkey can act on the frontmost window.
4. Window tracking uses Accessibility observers (moved, resized, minimized, destroyed) under
   the Accessibility permission.

## Consequences

- Two permissions: Screen Recording and Accessibility. macOS re-confirms Screen Recording
  monthly since 15.0; this is accepted.
- While another app is in front the pinned window is a mirror with about one frame of
  latency and no keyboard input. A click activates the real window and hides the mirror.
- No SIP changes, no private APIs, no injection. Works on stock macOS 26 and should survive
  OS updates, since every API used is public and undeprecated in the macOS 26 SDK.
- Windows that refuse capture (`NSWindowSharingNone`) cannot be pinned.

## Alternatives considered

- **Private window-level calls via a scripting addition (yabai style):** real pinning, but
  needs SIP partially disabled on the machine. Rejected.
- **System picker only (`SCContentSharingPicker`):** no permissions and no monthly prompt,
  but the app never sees the window list, so no hotkey on the frontmost window. May be added
  later as an opt-in mode.
- **iTerm2's own floating hotkey window:** solves iTerm2 only, and only for a dedicated
  hotkey window, not existing windows. Not general.
