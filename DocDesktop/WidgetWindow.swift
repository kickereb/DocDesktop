import AppKit

final class WidgetWindow: NSPanel {
    var prepareForInteraction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
