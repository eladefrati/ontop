---
title: "ADR-0006: Click forwarding replays the gesture once the window is in front"
status: Accepted
date: 2026-10-21
---

# ADR-0006: Click forwarding

**Status:** Accepted

## Context

The mirror is ontop's own window (ADR-0001), so a click on it reaches ontop and not the
pinned window. To pass the click on, ontop raises the real window and posts the click again
at the same screen point. A posted click goes to whatever window is on top at that point
when the click arrives.

The first build hid the mirror, raised the window, and posted a plain left click 80 ms
later. A window that took longer than 80 ms to come forward lost the click to the window
underneath. Right-clicks, modifier keys, and drags never reached the window, because the
post was always one left click.

A sheet is a window of its own. Over an open sheet, the top window at the point is the
sheet, not the pinned window.

## Decision

1. The first mouse-down on the mirror raises the real window.
2. ontop records the gesture from that press until every button is up: each down, drag,
   and up, with its button, location, and modifier keys.
3. After the last button is up, ontop checks once per frame. It replays the gesture when
   the window's app is frontmost and owns the top window at the point of the first press.
   That window is the pinned window or its sheet. A shown mirror belongs to ontop, so it
   fails the check.
4. If the check does not pass within 1 s, ontop drops the gesture and beeps. The first line
   of its menu then names the window that did not come to the front.
5. Each replayed event is a new event. A copy of the mirror's event keeps the routing that
   the window server gave the original, and a posted copy lands on the mirror again.

## Consequences

- A click reaches the pinned window's app or is dropped with a beep. It never lands on a
  window underneath.
- Right-clicks, modifier keys, and drags reach the window.
- ontop posts nothing while a button is down. A drag takes effect only on release, and the
  window shows no feedback during the drag.
- ontop delivers one gesture at a time and ignores a click on the mirror while it delivers
  the previous one. A double-click registers only if the mirror has hidden before the
  second click, which then goes straight to the real window.
- When a sheet is wider than its window, the mirror shrinks the window and the sheet
  together to the window's width (measured 2026-10-22: TextEdit's Save As sheet, 880 pt
  wide on a 640 pt window, at 73 %). A click on the sheet in the mirror lands at a
  different place on the real sheet.
- Delivery reads the window list once per frame, for at most 1 s per click.

## Alternatives considered

- **Post a plain left click 80 ms after raising the window (the first build):** no
  recording and no check. A slow window lost the click to the window underneath, and only
  left clicks reached the window. Replaced on 2026-10-21.
