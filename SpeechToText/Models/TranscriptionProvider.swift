import Foundation

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case appleSpeech
    case groq
    case localOpenAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .groq:
            return "Groq"
        case .localOpenAICompatible:
            return "Local OpenAI-Compatible"
        }
    }

    var detailText: String {
        switch self {
        case .appleSpeech:
            return "Live partial transcription with Apple's built-in speech recognizer."
        case .groq:
            return "Fast cloud transcription via Groq's OpenAI-compatible audio API."
        case .localOpenAICompatible:
            return "Use a local server that exposes an OpenAI-compatible transcription endpoint."
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .appleSpeech:
            return ""
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .localOpenAICompatible:
            return "http://localhost:8000/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .appleSpeech:
            return ""
        case .groq:
            return "whisper-large-v3"
        case .localOpenAICompatible:
            return "whisper-1"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .appleSpeech, .localOpenAICompatible:
            return false
        case .groq:
            return true
        }
    }

    var requiresSpeechRecognitionPermission: Bool {
        self == .appleSpeech
    }
}
