---
title: "ADR-0002: SwiftPM executable, Makefile bundle, Apple Development signing"
status: Accepted
date: 2026-10-16
---

# ADR-0002: Build and packaging

**Status:** Accepted

## Context

ontop is a single-developer, locally installed menu bar app. It needs an `.app` bundle with an
`Info.plist` (menu bar only, no Dock icon) and a stable code signature:
the Screen Recording and Accessibility grants are keyed to the signing identity, so an ad-hoc
signature loses both grants on every rebuild.

## Decision

1. **SwiftPM executable target**, Swift 6, AppKit, no dependencies. No Xcode project; all
   build inputs are text files under version control.
2. **A `Makefile` assembles the bundle:** `make app`, the default goal, builds release, lays
   out `build/ontop.app/Contents/{MacOS,Resources,Info.plist}`, and codesigns. `make install`
   quits a running ontop, copies the bundle to `/Applications`, and reopens it if it was
   running, because copying over a running bundle leaves the old code running.
   `make uninstall` removes it. `make run` launches the build.
3. **Sign with an Apple Development certificate** from a free personal team, identity
   selected by a `SIGN_IDENTITY` make variable. It defaults to the first Apple Development
   identity's SHA-1 hash, because codesign rejects a name that two certificates share, as a
   renewed certificate and the one it replaces do. Falls back to ad-hoc signing with a
   printed warning when none is found.
4. **No sandbox, no restricted entitlements**, so no provisioning profile is needed.

## Consequences

- Rebuilds keep their permission grants once a certificate is installed.
- Building needs only Xcode's command line tools and SDK. Creating the free certificate
  needs full Xcode, once.
- Notarization and distribution are out of scope. Adding them later means a Developer ID
  certificate and a notarization step in the Makefile, not a change of build system.

## Alternatives considered

- **Xcode project:** gives signing and bundle assembly for free, but a binary-ish
  `.pbxproj` in git and GUI-only settings. Not worth it for one target.
- **xcodegen or tuist:** generates the project from YAML. Extra tool for what a short
  Makefile does.
