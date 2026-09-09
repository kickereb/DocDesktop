import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var desktopWindowController: DesktopWindowController?
    private var globalHotKeyManager: GlobalHotKeyManager?
    private weak var previousApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBarItem()
        configureGlobalHotKey()
        _ = ensureOverlayController()
    }

    private func configureGlobalHotKey() {
        globalHotKeyManager = GlobalHotKeyManager { [weak self] in
            self?.popUpDocumentWindow()
        }
        globalHotKeyManager?.register()
    }

    private func configureMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "DocDesktop")
        statusItem?.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Show DocDesktop", action: #selector(showDocumentWindow), keyEquivalent: "d", modifiers: [.command, .shift]))
        menu.addItem(menuItem(title: "Hide DocDesktop", action: #selector(hideDocumentWindow)))
        menu.addItem(menuItem(title: "Change Document", action: #selector(changeDocument)))
        menu.addItem(menuItem(title: "Refresh", action: #selector(refreshDocuments)))
        menu.addItem(menuItem(title: "Open in Google Docs", action: #selector(openInGoogleDocs)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledMenuItem(title: "Settings"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Sign Out", action: #selector(signOut)))
        menu.addItem(menuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !modifiers.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private func disabledMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc func showDocumentWindow() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        showOverlay()
    }

    @objc private func popUpDocumentWindow() {
        toggleOverlay()
    }

    @objc func hideDocumentWindow() {
        hideOverlay()
    }

    @objc private func changeDocument() {
        showOverlay()
        NotificationCenter.default.post(name: .showDocumentPicker, object: nil)
    }

    @objc private func refreshDocuments() {
        NotificationCenter.default.post(name: .showDocumentPicker, object: nil)
    }

    @objc private func openInGoogleDocs() {
        guard let document = ActiveDocumentStore().load(), let url = document.webViewLink else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func signOut() {
        GoogleAuthManager.shared.signOut()
        ActiveDocumentStore().clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func toggleOverlay() {
        let controller = ensureOverlayController()
        if controller.isOverlayVisible {
            hideOverlay()
        } else {
            previousApplication = NSWorkspace.shared.frontmostApplication
            showOverlay()
        }
    }

    private func showOverlay() {
        ensureOverlayController().showOverlay()
    }

    private func hideOverlay() {
        desktopWindowController?.hideOverlay()
    }

    private func ensureOverlayController() -> DesktopWindowController {
        if let desktopWindowController {
            return desktopWindowController
        }

        let controller = DesktopWindowController()
        controller.onHide = { [weak self] in
            self?.restorePreviousApplication()
        }
        desktopWindowController = controller
        return controller
    }

    private func restorePreviousApplication() {
        guard let previousApplication,
              !previousApplication.isTerminated,
              previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        previousApplication.activate(options: [])
        self.previousApplication = nil
    }
}
