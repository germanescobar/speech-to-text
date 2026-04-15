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
    var finalTranscript: String
    var message: String?
    var startedAt: Date?

    static let idle = DictationSessionState(
        phase: .idle,
        finalTranscript: "",
        message: nil,
        startedAt: nil
    )

    static func listening(startedAt: Date) -> DictationSessionState {
        DictationSessionState(
            phase: .listening,
            finalTranscript: "",
            message: "Recording…",
            startedAt: startedAt
        )
    }

    static func processing() -> DictationSessionState {
        DictationSessionState(
            phase: .processing,
            finalTranscript: "",
            message: "Processing…",
            startedAt: nil
        )
    }

    static func completed(text: String, message: String) -> DictationSessionState {
        DictationSessionState(
            phase: .completed,
            finalTranscript: text,
            message: message,
            startedAt: nil
        )
    }

    static func failed(message: String) -> DictationSessionState {
        DictationSessionState(
            phase: .failed,
            finalTranscript: "",
            message: message,
            startedAt: nil
        )
    }
}
