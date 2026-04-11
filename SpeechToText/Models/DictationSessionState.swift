import Foundation

enum DictationSessionPhase: String, Codable, Equatable {
    case idle
    case requestingPermissions
    case listening
    case processing
    case completed
    case failed
}

struct DictationSessionState: Equatable {
    var phase: DictationSessionPhase
    var partialTranscript: String
    var finalTranscript: String
    var message: String?
    var startedAt: Date?

    static let idle = DictationSessionState(
        phase: .idle,
        partialTranscript: "",
        finalTranscript: "",
        message: nil,
        startedAt: nil
    )

    static func listening(startedAt: Date) -> DictationSessionState {
        DictationSessionState(
            phase: .listening,
            partialTranscript: "",
            finalTranscript: "",
            message: "Listening…",
            startedAt: startedAt
        )
    }

    static func processing(partialTranscript: String) -> DictationSessionState {
        DictationSessionState(
            phase: .processing,
            partialTranscript: partialTranscript,
            finalTranscript: "",
            message: "Processing…",
            startedAt: nil
        )
    }

    static func completed(text: String, message: String) -> DictationSessionState {
        DictationSessionState(
            phase: .completed,
            partialTranscript: text,
            finalTranscript: text,
            message: message,
            startedAt: nil
        )
    }

    static func failed(message: String) -> DictationSessionState {
        DictationSessionState(
            phase: .failed,
            partialTranscript: "",
            finalTranscript: "",
            message: message,
            startedAt: nil
        )
    }
}
