import XCTest
@testable import SpeechToText

final class SettingsStoreTests: XCTestCase {
    func testSettingsPersistValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = SettingsStore(userDefaults: defaults)
        store.shortcut = HotkeyShortcut(keyCode: 1, modifiers: 2)
        store.autoPasteEnabled = true
        store.historyLimit = 12
        store.transcriptionProvider = .groq
        store.transcriptionAPIKey = "test-key"
        store.transcriptionBaseURL = "https://example.com/v1"
        store.transcriptionModel = "whisper-large-v3"
        store.markOnboardingCompleted()

        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.shortcut, HotkeyShortcut(keyCode: 1, modifiers: 2))
        XCTAssertTrue(reloaded.autoPasteEnabled)
        XCTAssertEqual(reloaded.historyLimit, 12)
        XCTAssertEqual(reloaded.transcriptionProvider, .groq)
        XCTAssertEqual(reloaded.transcriptionAPIKey, "test-key")
        XCTAssertEqual(reloaded.transcriptionBaseURL, "https://example.com/v1")
        XCTAssertEqual(reloaded.transcriptionModel, "whisper-large-v3")
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
