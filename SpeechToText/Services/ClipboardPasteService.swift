import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class ClipboardPasteService {
    func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteInto(_ app: NSRunningApplication?) async -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        if let app {
            _ = app.activate()
            try? await Task.sleep(for: .milliseconds(180))
        }

        return postPasteShortcut()
    }

    private func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
