import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(controller: AppController) {
        let rootView = SettingsView(controller: controller)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "SpeechToText Settings"
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
