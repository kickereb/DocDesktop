import AppKit

final class WidgetWindow: NSPanel {
    var prepareForInteraction: (() -> Void)?
    var hideOverlay: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        hideOverlay?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            hideOverlay?()
            return
        }

        super.keyDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            prepareForInteraction?()
        default:
            break
        }

        super.sendEvent(event)
    }
}
