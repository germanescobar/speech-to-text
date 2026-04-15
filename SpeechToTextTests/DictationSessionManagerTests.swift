import XCTest
@testable import SpeechToText

@MainActor
final class DictationSessionManagerTests: XCTestCase {
    func testStartTransitionsToListeningWhenPermissionsGranted() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: true, speechGranted: true)
        let speech = TestSpeechTranscriber()
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionServiceFactory: { speech }
        )

        await manager.start()

        XCTAssertEqual(manager.state.phase, .listening)
    }

    func testStopTransitionsToCompletedWithNormalizedTranscript() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: true, speechGranted: true)
        let speech = TestSpeechTranscriber(finalTranscript: " hello   world ")
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionServiceFactory: { speech }
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
            transcriptionServiceFactory: { speech }
        )

        await manager.start()

        XCTAssertEqual(manager.state.phase, .failed)
    }

    func testStartSkipsSpeechPermissionForNonAppleProvider() async {
        let permissions = TestPermissionsCoordinator(microphoneGranted: true, speechGranted: false)
        let speech = TestSpeechTranscriber(requiresSpeechRecognitionPermission: false)
        let manager = DictationSessionManager(
            permissionsCoordinator: permissions,
            transcriptionServiceFactory: { speech }
        )

        await manager.start()

        XCTAssertEqual(manager.state.phase, .listening)
        XCTAssertEqual(permissions.speechPermissionRequests, 0)
    }
}

@MainActor
private final class TestPermissionsCoordinator: PermissionsCoordinator, @unchecked Sendable {
    private let microphoneGrantedValue: Bool
    private let speechGrantedValue: Bool
    private(set) var speechPermissionRequests = 0

    init(microphoneGranted: Bool, speechGranted: Bool) {
        self.microphoneGrantedValue = microphoneGranted
        self.speechGrantedValue = speechGranted
    }

    override func requestMicrophoneIfNeeded() async -> Bool {
        microphoneGrantedValue
    }

    override func requestSpeechRecognitionIfNeeded() async -> Bool {
        speechPermissionRequests += 1
        return speechGrantedValue
    }
}

private final class TestSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let finalTranscript: String
    let requiresSpeechRecognitionPermission: Bool

    init(
        finalTranscript: String = "test transcript",
        requiresSpeechRecognitionPermission: Bool = true
    ) {
        self.finalTranscript = finalTranscript
        self.requiresSpeechRecognitionPermission = requiresSpeechRecognitionPermission
    }

    func startRecording() throws {}

    func stopRecordingAndTranscribe(locale: Locale) async throws -> String {
        _ = locale
        return finalTranscript
    }

    func cancel() {}
}
