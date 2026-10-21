# Pin with the hotkey

Ctrl+Option+P pins the frontmost window; pressing it again while that window is in front
unpins it. The menu marks pinned windows with a check.

## Sub-features

- `hotkey-pin` the press pins the frontmost app's front window.
- `hotkey-unpin` a second press with the pinned window in front unpins it.
- `hotkey-menu-state` the menu's check mark follows.

## How to get to it (user POV)

- Bring the window to the front and press Ctrl+Option+P (or the chord set with Change Shortcut).

## Driving it with verify.py and probe

Preconditions:

- Baseline; target A unpinned.

- **Front.** `probe ax-raise <TextEdit pid> ontop-verify-a.txt`. `probe front` is TextEdit.
- **Pin.** `probe hotkey`. The log gains `pinned <private> (<target id>)`; ontop now owns one layer-3 window whose bounds equal the target's.
- **Menu.** `probe menu list <pid>`. `ontop-verify-a.txt` under `TextEdit` is checked.
- **Unpin.** Raise the target again, `probe hotkey`. The log gains `unpinned <target id>`; the mirror is off screen; the menu item is unchecked.

## Gotchas

- The hotkey acts on the last frontmost app other than ontop. Raise the target explicitly; the terminal running the agent is otherwise the frontmost app.
- The probe presses only the default chord. With a custom shortcut set (defaults key `chord`) the doctor refuses.
- While the pinned window is frontmost its mirror exists at alpha 0. "Gone" is off screen, not alpha 0.
