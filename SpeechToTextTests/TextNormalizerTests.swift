import XCTest
@testable import SpeechToText

final class TextNormalizerTests: XCTestCase {
    func testNormalizeTrimsAndCollapsesWhitespace() {
        let normalized = TextNormalizer.normalize("  hello   world \n\n again  ")
        XCTAssertEqual(normalized, "hello world again")
    }

    func testNormalizeReturnsEmptyStringForBlankInput() {
        XCTAssertEqual(TextNormalizer.normalize("   \n  "), "")
    }
}
