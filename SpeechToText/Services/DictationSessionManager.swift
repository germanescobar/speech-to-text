import Foundation

@MainActor
final class DictationSessionManager: ObservableObject {
    @Published private(set) var state: DictationSessionState = .idle

    private let permissionsCoordinator: PermissionsCoordinator
    private let transcriptionServiceFactory: () -> SpeechTranscribing
    private let locale: Locale
    private var transcriptionService: SpeechTranscribing?

    init(
        permissionsCoordinator: PermissionsCoordinator,
        transcriptionServiceFactory: @escaping () -> SpeechTranscribing,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.permissionsCoordinator = permissionsCoordinator
        self.transcriptionServiceFactory = transcriptionServiceFactory
        self.locale = locale
    }

    func start() async {
        guard canStart else {
            return
        }

        state = DictationSessionState(
            phase: .requestingPermissions,
            finalTranscript: "",
            message: "Requesting permissions…",
            startedAt: nil
        )

        let microphoneGranted = await permissionsCoordinator.requestMicrophoneIfNeeded()
        guard microphoneGranted else {
            state = .failed(message: "Microphone access is required to start dictation.")
            return
        }

        let transcriptionService = transcriptionServiceFactory()
        self.transcriptionService = transcriptionService

        if transcriptionService.requiresSpeechRecognitionPermission {
            let speechGranted = await permissionsCoordinator.requestSpeechRecognitionIfNeeded()
            guard speechGranted else {
                state = .failed(message: "Speech recognition access is required to transcribe dictation.")
                self.transcriptionService = nil
                return
            }
        }

        do {
            try transcriptionService.startRecording()
            state = .listening(startedAt: Date())
        } catch {
            self.transcriptionService = nil
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() async -> String? {
        guard state.phase == .listening, let transcriptionService else {
            return nil
        }

        state = .processing()

        do {
            let transcript = try await transcriptionService.stopRecordingAndTranscribe(locale: locale)
            self.transcriptionService = nil
            let normalized = TextNormalizer.normalize(transcript)

            guard !normalized.isEmpty else {
                state = .failed(message: "No speech was detected.")
                return nil
            }

            state = .completed(text: normalized, message: "Copied to clipboard.")
            return normalized
        } catch {
            self.transcriptionService = nil
            state = .failed(message: error.localizedDescription)
            return nil
        }
    }

    func cancel() {
        transcriptionService?.cancel()
        transcriptionService = nil
        state = .idle
    }

    func setCompletionMessage(_ message: String) {
        guard state.phase == .completed else {
            return
        }

        state = .completed(text: state.finalTranscript, message: message)
    }

    private var canStart: Bool {
        switch state.phase {
        case .idle, .completed, .failed:
            return true
        case .requestingPermissions, .listening, .processing:
            return false
        }
    }
}
