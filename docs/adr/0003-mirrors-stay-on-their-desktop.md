---
title: "ADR-0003: Mirrors stay on their window's desktop by default"
status: Accepted
date: 2026-10-16
---

# ADR-0003: Mirrors stay on their desktop

**Status:** Accepted

## Context

The [proposal](../proposal.md) put mirrors on every desktop (Space) and over full-screen
apps, so a pinned window followed the user everywhere. In use, that is not always wanted: a
window pinned on one desktop can be meant for that desktop only. The real window cannot be
moved by ontop, and macOS offers no public way to place a window on a chosen desktop; a
window simply belongs to the desktop that is active when it is first ordered in. A window
that stops joining all desktops stays on the desktop that is active at that moment.

## Decision

1. Mirrors stay on the desktop of their window by default. A menu toggle, "Follow Across
   Desktops", restores the all-desktops behaviour; it applies to current and future pins.
2. To land on the right desktop, the mirror is ordered in at pin time, fully transparent
   and ignoring clicks. Pinning happens from the window's own desktop, since the menu lists
   only windows on the active desktop and the shortcut acts on the frontmost one.
3. Showing and hiding is done with transparency, not by removing the window, so the
   desktop assignment survives. The exception is turning Follow off while a mirror's
   desktop is not active, since the mirror would stay on the active desktop. That mirror is
   ordered out, and ordered in again the first time its window is on screen, which is when
   the window's desktop is active.
4. A mirror whose desktop is not active is treated as hidden and its stream stopped; a
   desktop switch re-evaluates every pin.

## Consequences

- A pinned window moved to another desktop by the user through Mission Control leaves its
  mirror behind. Unpin and pin again on the new desktop. Following the move would need
  private window-server APIs, which ADR-0001 rules out.
- The capture runs only when the mirror can be seen, which is cheaper than before when the
  user works on another desktop.
- An invisible window exists per pin, except from the moment Follow is turned off away from
  the window's desktop until that desktop is next active. It ignores mouse events and is
  excluded from ontop's own window list.

## Alternatives considered

- **Keep all-desktops only:** simplest, but forces the behaviour on everyone.
- **Private Space APIs** to assign the mirror to the window's Space and follow moves:
  rejected by ADR-0001.
