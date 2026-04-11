import Carbon
import Dispatch
import Foundation

final class HotkeyManager {
    fileprivate static let hotkeySignature = OSType(0x53545458)
    nonisolated(unsafe) fileprivate static var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) fileprivate static var onKeyPressed: (@Sendable () -> Void)?

    private var hotKeyRef: EventHotKeyRef?

    init() {
        Self.installHandlerIfNeeded()
    }

    func register(shortcut: HotkeyShortcut, handler: @escaping @Sendable () -> Void) {
        Self.onKeyPressed = handler
        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.hotkeySignature, id: 1)
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
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
    }

    private static func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }
}

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard result == noErr, hotKeyID.signature == HotkeyManager.hotkeySignature else {
        return noErr
    }

    DispatchQueue.main.async {
        HotkeyManager.onKeyPressed?()
    }
    return noErr
}
