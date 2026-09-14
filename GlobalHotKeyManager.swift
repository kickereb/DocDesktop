import Carbon
import Foundation

final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: () -> Void
    private var isHotKeyDown = false

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else { return }

        var hotKeyID = EventHotKeyID(signature: 0x4444484B, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func handleEvent(kind: UInt32) {
        switch kind {
        case UInt32(kEventHotKeyPressed):
            handlePressed()
        case UInt32(kEventHotKeyReleased):
            isHotKeyDown = false
        default:
            break
        }
    }

    private func handlePressed() {
        guard !isHotKeyDown else { return }
        isHotKeyDown = true
        DispatchQueue.main.async { [onTrigger] in
            onTrigger()
        }
    }
}

private func globalHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleEvent(kind: GetEventKind(event))
    return noErr
}
