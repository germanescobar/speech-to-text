import XCTest
@testable import SpeechToText

@MainActor
final class DictationSessionManagerTests: XCTestCase {
    func testStartTransitionsToListeningWhenPermissionsGranted() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: true, speechGranted: true)
        let speech = TestSpeechTranscriber()
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionService: speech
        )

        await manager.start()

        XCTAssertEqual(manager.state.phase, .listening)
    }

    func testStopTransitionsToCompletedWithNormalizedTranscript() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: true, speechGranted: true)
        let speech = TestSpeechTranscriber(finalTranscript: " hello   world ")
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionService: speech
        )

        await manager.start()
        let transcript = await manager.stop()

        XCTAssertEqual(transcript, "hello world")
        XCTAssertEqual(manager.state.phase, .completed)
        XCTAssertEqual(manager.state.finalTranscript, "hello world")
    }

    func testStartFailsWhenMicrophoneDenied() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: false, speechGranted: true)
        let speech = TestSpeechTranscriber()
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionService: speech
        )

        await manager.start()

        XCTAssertEqual(manager.state.phase, .failed)
    }
}

@MainActor
private final class TestPermissionsCoordinator: PermissionsCoordinator {
    private let microphoneGrantedValue: Bool
    private let speechGrantedValue: Bool

    init(microphoneGranted: Bool, speechGranted: Bool) {
        self.microphoneGrantedValue = microphoneGranted
        self.speechGrantedValue = speechGranted
    }

    override func requestMicrophoneIfNeeded() async -> Bool {
        microphoneGrantedValue
    }

    override func requestSpeechRecognitionIfNeeded() async -> Bool {
        speechGrantedValue
    }
}

private final class TestSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let finalTranscript: String

    init(finalTranscript: String = "test transcript") {
        self.finalTranscript = finalTranscript
    }

    func startTranscribing(locale: Locale, onPartialResult: @escaping @Sendable (String) -> Void) throws {
        onPartialResult(finalTranscript)
    }

    func stopTranscribing() async throws -> String {
        finalTranscript
    }

    func cancel() {}
}
