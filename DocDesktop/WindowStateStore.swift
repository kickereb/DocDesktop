import AppKit

struct WindowStateStore {
    private static let frameKey = "overlayPanelFrame"
    private static let legacyFrameKey = "desktopWidgetFrame"
    private static let defaultSize = NSSize(width: 680, height: 720)

    var hasSavedFrame: Bool {
        UserDefaults.standard.string(forKey: Self.frameKey) != nil
    }

    func restoredFrame() -> NSRect {
        let savedFrameString = UserDefaults.standard.string(forKey: Self.frameKey)
            ?? UserDefaults.standard.string(forKey: Self.legacyFrameKey)

        guard
            let frameString = savedFrameString,
            let frame = NSRectFromString(frameString).standardized.validWidgetFrame
        else {
            return defaultFrame()
        }

        return frame
    }

    func save(frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    private func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visibleFrame.midX - Self.defaultSize.width / 2,
            y: visibleFrame.midY - Self.defaultSize.height / 2
        )
        return NSRect(origin: origin, size: Self.defaultSize)
    }
}

private extension NSRect {
    var validWidgetFrame: NSRect? {
        guard width >= 420, height >= 400 else { return nil }

        let screens = NSScreen.screens.map(\.visibleFrame)
        let isVisible = screens.contains { screenFrame in
            screenFrame.intersects(self)
        }

        return isVisible ? self : nil
    }
}
