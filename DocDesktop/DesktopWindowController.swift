import AppKit
import SwiftUI

final class DesktopWindowController: NSWindowController, NSWindowDelegate {
    private let stateStore = WindowStateStore()
    var onHide: (() -> Void)?

    init() {
        let contentView = ContentView()
        let window = WidgetWindow(
            contentRect: stateStore.restoredFrame(),
            styleMask: [.titled, .fullSizeContentView, .resizable],
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
        window.minSize = NSSize(width: 420, height: 400)
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        window.hideOverlay = { [weak self] in
            self?.hideOverlay()
        }
        hideTitleBarButtons(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func prepareForInteraction() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showOverlay() {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        centerIfNeeded(window)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusDocumentEditor, object: nil)
        }
    }

    func hideOverlay() {
        guard let window else { return }
        saveWindowFrame()
        NotificationCenter.default.post(name: .saveDocumentNow, object: nil)
        window.orderOut(nil)
        onHide?()
    }

    var isOverlayVisible: Bool {
        window?.isVisible == true
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

    private func centerIfNeeded(_ window: NSWindow) {
        guard !stateStore.hasSavedFrame else { return }
        window.center()
    }
}
