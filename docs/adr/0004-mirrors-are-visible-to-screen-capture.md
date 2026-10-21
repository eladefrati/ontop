---
title: "ADR-0004: Mirrors are visible to screen capture"
status: Accepted
date: 2026-10-20
---

# ADR-0004: Mirrors are visible to screen capture

**Status:** Accepted

## Context

The [proposal](../proposal.md) set the mirror window's sharing type to none, so that ontop
would never capture its own mirrors. That setting hides the mirror from every capture
client, not only from ontop: screenshots, screen recordings and screen sharing in video
calls all show the screen as if nothing were pinned. What the user sees and what they
share differ, which reads as a bug.

The protection it was meant to give is already provided elsewhere. Each stream uses a
desktop-independent window filter, which delivers only the target window's own content,
whatever is stacked above it, so a mirror never appears inside another pin's stream.
ontop's window list also leaves out ontop's own windows, so a mirror cannot be pinned.

## Decision

The mirror window keeps the default sharing type. Mirrors appear in screenshots, screen
recordings and screen sharing exactly as they appear on screen.

## Consequences

- Shared and recorded screens match what the user sees, pinned windows included.
- A pinned window's content reaches whoever is watching a screen share, as it would if the
  window were simply in front. Users who do not want that unpin before sharing.

## Alternatives considered

- **Keep the mirror hidden from capture:** keeps a pinned window private during screen
  sharing, but the shared screen no longer matches the user's, and nothing else depends
  on it.
- **A menu toggle:** no case found where hiding is the better default; it can be added if
  one comes up.
