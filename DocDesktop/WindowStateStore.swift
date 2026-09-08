import AppKit

struct WindowStateStore {
    private static let frameKey = "desktopWidgetFrame"
    private static let defaultSize = NSSize(width: 420, height: 540)

    func restoredFrame() -> NSRect {
        guard
            let frameString = UserDefaults.standard.string(forKey: Self.frameKey),
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
            x: visibleFrame.maxX - Self.defaultSize.width - 32,
            y: visibleFrame.maxY - Self.defaultSize.height - 32
        )
        return NSRect(origin: origin, size: Self.defaultSize)
    }
}

private extension NSRect {
    var validWidgetFrame: NSRect? {
        guard width >= 320, height >= 360 else { return nil }

        let screens = NSScreen.screens.map(\.visibleFrame)
        let isVisible = screens.contains { screenFrame in
            screenFrame.intersects(self)
        }

        return isVisible ? self : nil
    }
}
