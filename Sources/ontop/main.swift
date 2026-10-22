import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
// ontop makes every Accessibility call on the main thread, where a call to an app that does
// not answer waits out the messaging timeout. Set on the system-wide element, the limit
// covers every element, not only the one it is set on. An app that does not answer then
// costs the menu or the hotkey half a second: its first call, for the window list, times out.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
app.run()
