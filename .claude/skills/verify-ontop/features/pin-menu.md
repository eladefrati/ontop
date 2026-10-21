# Pin from the menu

The menu lists every pinnable window, grouped under its app. Choosing one toggles its pin;
"Pin Frontmost Window" pins the window that was in front before the menu opened; "Unpin All"
clears every pin and is disabled when there are none.

## Sub-features

- `menu-window` choosing a window item pins it, choosing it again unpins it.
- `menu-frontmost` Pin Frontmost Window pins the window that was in front.
- `menu-unpin-all` Unpin All unpins everything; disabled with no pins.

## How to get to it (user POV)

- Click the pin icon in the menu bar, then a window title under its app, Pin Frontmost Window, or Unpin All.

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A unpinned.

- **Pin by title.** `probe menu click <pid> ontop-verify-a.txt --section TextEdit`. Log `pinned <private> (<id>)`, one mirror, item checked.
- **Unpin by title.** The same click again. Log `unpinned <id>`, mirror off screen.
- **Pin Frontmost Window.** Raise the target, `probe menu click <pid> "Pin Frontmost Window"`. Log `pinned … (<id>)`.
- **Unpin All.** `Unpin All` is enabled; choose it. Log `unpinned <id>`; reopened, `Unpin All` is disabled.

## Gotchas

- Window titles are not unique across apps (two "Untitled" documents); always pass `--section`.
- The menu lists only windows on the active desktop.
- Choosing Pin Frontmost Window by its key equivalent fires the global hotkey too; the app ignores the menu's keyDown so the pin toggles once. The probe presses the item through Accessibility, which is a click, not a keyDown.
