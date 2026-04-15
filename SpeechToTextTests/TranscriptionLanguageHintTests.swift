import XCTest
@testable import SpeechToText

final class TranscriptionLanguageHintTests: XCTestCase {
    func testReturnsLanguageCodeFromLocaleIdentifier() {
        XCTAssertEqual(TranscriptionLanguageHint.from(locale: Locale(identifier: "es_CO")), "es")
        XCTAssertEqual(TranscriptionLanguageHint.from(locale: Locale(identifier: "en-US")), "en")
    }

    func testReturnsNilForInvalidLocaleIdentifier() {
        XCTAssertNil(TranscriptionLanguageHint.from(locale: Locale(identifier: "")))
    }
}
