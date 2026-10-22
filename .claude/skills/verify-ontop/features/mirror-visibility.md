# Mirror visibility

While another app is in front, a live mirror of the pinned window floats above everything at
the window's position. When the pinned window itself is in front, the mirror hides and the
real window is what the user sees.

## Sub-features

- `mirror-hidden-front` hidden while the pinned window, or a sheet on it, is its app's focused window and the app is frontmost (sheets: see sheet-click).
- `mirror-shown-other` shown, with the window's content, while another app is frontmost.
- `mirror-hidden-again` hidden again once the pinned window returns to the front.

## How to get to it (user POV)

- Pin a window, then switch to another app (click it, Cmd+Tab), then back.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A pinned with the hotkey while frontmost.

- **Pinned window in front.** Mirror alpha 0. Capture `NNN-mirror-visibility-hidden-target-front.png` (expected empty).
- **Another app in front.** `probe activate <cover pid>`. Mirror alpha 1 and on screen; log `[…:mirror] shown at <private>`; `screencapture -l <mirror id>` gives `NNN-mirror-visibility-shown-cover-front.png` with opaque > 0.9, showing the document's lines. The cover is captured too, for comparison.
- **Back.** `probe ax-raise` the target. Mirror alpha 0; log `[…:mirror] hidden`.

## Gotchas

- `screencapture -l` of a hidden mirror is a transparent image by design; the alpha from the window server is the proof of hidden, the image is the proof of content when shown.
- The first frames land a few hundred ms after `shown`; capture after 0.5 s.
- Another window of the same app in front also shows the mirror (the rule is "frontmost app and focused window"). The journey uses a different app; the desktops journey hits the same-app case with target B.
