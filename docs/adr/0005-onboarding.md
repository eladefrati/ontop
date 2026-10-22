---
title: "ADR-0005: Onboarding relies on macOS's prompts and a relaunch"
status: Accepted
date: 2026-10-21
---

# ADR-0005: Onboarding

**Status:** Accepted

## Context

ontop needs Accessibility and Screen Recording (ADR-0001). The [proposal](../proposal.md)
had ontop show one alert per missing permission that explains why and opens its Privacy &
Security pane. The request that adds ontop to the Accessibility list also shows macOS's own
prompt, so the user saw two dialogs per permission.

The first build created its menu bar item only after both permissions were granted. ontop
has no Dock icon, so a user who had not granted them had a running process with no icon and
no Quit.

Screen Recording on macOS 26 adds two constraints, measured on 2026-10-21:

- Requesting it shows macOS's prompt but does not add ontop to the Screen & System Audio
  Recording list. The user adds ontop with +.
- A running process never sees a grant made after it started. `CGPreflightScreenCaptureAccess`
  keeps its launch value. Asking ScreenCaptureKit instead counts as a capture attempt, and
  macOS shows its prompt again on every check.

Accessibility has neither constraint. `AXIsProcessTrusted` reports a grant in the running
process.

## Decision

1. The menu bar item and Quit exist from launch. While a permission is missing, the icon is
   a slashed pin and the menu says which permission is missing and why, and offers Open
   System Settings.
2. ontop asks macOS for each missing permission once per launch, Accessibility first, and
   shows no dialog of its own. macOS's prompt is the one dialog per permission.
3. ontop checks Accessibility every second until it is granted.
4. ontop does not check for a Screen Recording grant after asking. The user restarts ontop,
   either through the Quit & Reopen that macOS offers when ontop is turned on, or through
   the menu's Relaunch ontop.

## Consequences

- A user who denies or ignores a prompt still has the icon, the reason, and Quit.
- Granting Screen Recording always takes a restart. The menu's reason line tells the user to
  add ontop with +, turn it on, and choose Quit & Reopen.
- Relaunch ontop removes the menu bar item before it opens the new instance, so two icons
  never show at once.
- After an ad-hoc rebuild the old entries in both lists still look turned on but no longer
  match the app (ADR-0002). The user removes them with - and adds the app again.

## Alternatives considered

- **ontop's own alert per permission (the proposal):** two dialogs for one permission, and
  the alert adds nothing the menu can't say.
- **Detect the Screen Recording grant and relaunch automatically:** polling
  `CGPreflightScreenCaptureAccess` never sees the grant. Polling ScreenCaptureKit sees it,
  but brings macOS's prompt back every second until the user grants or quits. Both were
  built and dropped on 2026-10-21.
