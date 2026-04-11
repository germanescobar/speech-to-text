import XCTest
@testable import SpeechToText

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testAddPersistsAndTrimsToLimit() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = HistoryStore(userDefaults: defaults, storageKey: "history")
        store.add(text: "One", limit: 2)
        store.add(text: "Two", limit: 2)
        store.add(text: "Three", limit: 2)

        XCTAssertEqual(store.recent.map(\.text), ["Three", "Two"])
    }

    func testClearRemovesEntries() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = HistoryStore(userDefaults: defaults, storageKey: "history")
        store.add(text: "One", limit: 2)
        store.clear()

        XCTAssertTrue(store.recent.isEmpty)
    }
}
