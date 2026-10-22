# Architecture decision records

Each ADR records one decision, the constraints behind it, and what it costs. The
[proposal](../proposal.md) is the original design. Where an ADR and the proposal disagree,
the ADR is current.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-mirror-overlay.md) | Pin by mirroring the window into a floating overlay | Accepted, Decision 1 amended by 0003 |
| [0002](0002-build-and-packaging.md) | SwiftPM executable, Makefile bundle, Apple Development signing | Accepted |
| [0003](0003-mirrors-stay-on-their-desktop.md) | Mirrors stay on their window's desktop by default | Accepted |
| [0004](0004-mirrors-are-visible-to-screen-capture.md) | Mirrors are visible to screen capture | Accepted |
| [0005](0005-onboarding.md) | Onboarding relies on macOS's prompts and a relaunch | Accepted |
| [0006](0006-click-forwarding.md) | Click forwarding replays the gesture once the window is in front | Accepted |
