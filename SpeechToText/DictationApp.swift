import SwiftUI

@main
struct DictationApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("SpeechToText", systemImage: controller.menuBarIconName) {
            MenuBarContentView(controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}
