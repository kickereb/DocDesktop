import AppKit
import SwiftUI

final class DesktopWindowController: NSWindowController, NSWindowDelegate {
    private let stateStore = WindowStateStore()

    init() {
        let contentView = ContentView()
        let window = WidgetWindow(
            contentRect: stateStore.restoredFrame(),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "DocDesktop"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = false
        window.worksWhenModal = true
        window.minSize = NSSize(width: 320, height: 360)
        window.level = Self.desktopWidgetLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.acceptsMouseMovedEvents = true
        window.delegate = nil
        window.contentView = NSHostingView(rootView: contentView)

        super.init(window: window)
        window.delegate = self
        window.prepareForInteraction = { [weak self] in
            self?.prepareForInteraction()
        }
        hideTitleBarButtons(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func prepareForInteraction() {
        guard let window else { return }
        window.level = Self.desktopWidgetLevel
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func returnToDesktopLevel() {
        guard let window else { return }
        window.level = Self.desktopWidgetLevel
        window.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let window else { return }
        stateStore.save(frame: window.frame)
    }

    private func hideTitleBarButtons(in window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private static var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)))
    }
}
