import AppKit

/// A small window that records a key combination and hands it back on Save. Another press
/// replaces the recorded chord; Cancel or Escape keeps the current one.
@MainActor
final class ChordRecorderWindow: NSWindow {
    private let recorder: RecorderView
    private let saveButton: NSButton
    private let original: KeyChord
    private var completion: ((KeyChord?) -> Void)?

    init(current: KeyChord) {
        original = current
        recorder = RecorderView(current: current)
        saveButton = NSButton(title: "Save", target: nil, action: nil)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "ontop Shortcut"
        isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: "Press the new shortcut for Pin Frontmost Window.")
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 120, width: 320, height: 24)
        recorder.frame = NSRect(x: 80, y: 68, width: 200, height: 36)
        recorder.onChange = { [weak self] in self?.updateSaveButton() }

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 160, y: 16, width: 90, height: 32)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 254, y: 16, width: 90, height: 32)

        let content = NSView(frame: contentRect(forFrameRect: frame))
        content.addSubview(label)
        content.addSubview(recorder)
        content.addSubview(cancel)
        content.addSubview(saveButton)
        contentView = content
        updateSaveButton()
    }

    func present(completion: @escaping (KeyChord?) -> Void) {
        self.completion = completion
        center()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(recorder)
    }

    private func updateSaveButton() {
        saveButton.isEnabled = recorder.current != original
    }

    @objc private func save() {
        finish(recorder.current)
    }

    @objc private func cancel() {
        finish(nil)
    }

    private func finish(_ chord: KeyChord?) {
        let completion = self.completion
        self.completion = nil
        close()
        completion?(chord)
    }

    // The title bar close button counts as Cancel.
    override func close() {
        super.close()
        if let completion {
            self.completion = nil
            completion(nil)
        }
    }
}

private final class RecorderView: NSView {
    private(set) var current: KeyChord
    var onChange: (() -> Void)?

    init(current: KeyChord) {
        self.current = current
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 2
        path.stroke()
        let text = current.display as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if let chord = KeyChord(event: event) {
            current = chord
            needsDisplay = true
            onChange?()
        } else {
            // Unmodified keys fall through so Return and Escape reach the buttons.
            super.keyDown(with: event)
        }
    }

    // Chords with Command would otherwise be taken as menu key equivalents.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard KeyChord(event: event) != nil else { return false }
        keyDown(with: event)
        return true
    }
}
