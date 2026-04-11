import Foundation

private final class SessionManagerBox: @unchecked Sendable {
    weak var value: DictationSessionManager?

    init(_ value: DictationSessionManager) {
        self.value = value
    }
}

@MainActor
final class DictationSessionManager: ObservableObject {
    @Published private(set) var state: DictationSessionState = .idle

    private let permissionsCoordinator: PermissionsCoordinator
    private let transcriptionService: SpeechTranscribing
    private let locale: Locale

    init(
        permissionsCoordinator: PermissionsCoordinator,
        transcriptionService: SpeechTranscribing,
        locale: Locale = Locale(identifier: "en_US")
    ) {
        self.permissionsCoordinator = permissionsCoordinator
        self.transcriptionService = transcriptionService
        self.locale = locale
    }

    func start() async {
        guard canStart else {
            return
        }

        state = DictationSessionState(
            phase: .requestingPermissions,
            partialTranscript: "",
            finalTranscript: "",
            message: "Requesting permissions…",
            startedAt: nil
        )

        let microphoneGranted = await permissionsCoordinator.requestMicrophoneIfNeeded()
        guard microphoneGranted else {
            state = .failed(message: "Microphone access is required to start dictation.")
            return
        }

        let speechGranted = await permissionsCoordinator.requestSpeechRecognitionIfNeeded()
        guard speechGranted else {
            state = .failed(message: "Speech recognition access is required to transcribe dictation.")
            return
        }

        do {
            try transcriptionService.startTranscribing(
                locale: locale,
                onPartialResult: Self.makePartialResultHandler(for: self)
            )

            state = .listening(startedAt: Date())
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() async -> String? {
        guard state.phase == .listening else {
            return nil
        }

        state = .processing(partialTranscript: state.partialTranscript)

        do {
            let transcript = try await transcriptionService.stopTranscribing()
            let normalized = TextNormalizer.normalize(transcript)

            guard !normalized.isEmpty else {
                state = .failed(message: "No speech was detected.")
                return nil
            }

            state = .completed(text: normalized, message: "Copied to clipboard.")
            return normalized
        } catch {
            state = .failed(message: error.localizedDescription)
            return nil
        }
    }

    func cancel() {
        transcriptionService.cancel()
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

    nonisolated private static func makePartialResultHandler(
        for manager: DictationSessionManager
    ) -> @Sendable (String) -> Void {
        let box = SessionManagerBox(manager)

        return { partial in
            Task { @MainActor in
                box.value?.state.partialTranscript = partial
            }
        }
    }
}
