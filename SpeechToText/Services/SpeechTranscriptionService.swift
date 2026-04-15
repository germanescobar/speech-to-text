@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

protocol SpeechTranscribing: AnyObject, Sendable {
    var requiresSpeechRecognitionPermission: Bool { get }

    func startRecording() throws
    func stopRecordingAndTranscribe(locale: Locale) async throws -> String
    func cancel()
}

enum SpeechTranscriptionError: LocalizedError {
    case recognizerUnavailable
    case audioEngineFailure
    case noSpeechDetected
    case silentAudio
    case invalidConfiguration(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable right now."
        case .audioEngineFailure:
            return "The microphone could not be started."
        case .noSpeechDetected:
            return "No speech was detected."
        case .silentAudio:
            return "Audio was captured, but it appears to be silent."
        case .invalidConfiguration(let message):
            return message
        case .uploadFailed(let message):
            return message
        }
    }
}

struct OpenAICompatibleTranscriptionConfiguration: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
}

enum TranscriptionLanguageHint {
    static func from(locale: Locale) -> String? {
        if let languageCode = locale.language.languageCode?.identifier,
           !languageCode.isEmpty {
            return languageCode
        }

        let identifier = locale.identifier
        let separators = CharacterSet(charactersIn: "_-")
        let components = identifier.components(separatedBy: separators)
        guard let first = components.first, !first.isEmpty else {
            return nil
        }
        return first.lowercased()
    }
}

private final class DictationAudioRecorder: @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() throws {
        cancel()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw SpeechTranscriptionError.audioEngineFailure
            }

            self.recorder = recorder
            self.fileURL = outputURL
            DiagnosticsLogger.shared.log(
                "Started audio recording",
                metadata: [
                    "file": outputURL.path,
                    "format": "wav",
                    "sampleRate": "16000",
                    "channels": "1"
                ]
            )
        } catch let error as SpeechTranscriptionError {
            DiagnosticsLogger.shared.log(
                "Failed to start audio recording",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        } catch {
            DiagnosticsLogger.shared.log(
                "Failed to start audio recording",
                metadata: ["error": error.localizedDescription]
            )
            throw SpeechTranscriptionError.audioEngineFailure
        }
    }

    func stop() throws -> URL {
        guard let recorder, let fileURL else {
            throw SpeechTranscriptionError.noSpeechDetected
        }

        let recordedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        DiagnosticsLogger.shared.log(
            "Stopped audio recording",
            metadata: [
                "file": fileURL.path,
                "durationSeconds": String(format: "%.2f", recordedDuration),
                "fileSizeBytes": String(fileSize)
            ]
        )

        if fileURL.pathExtension.lowercased() == "wav",
           let audioStats = audioStats(forPCM16MonoWavAt: fileURL) {
            DiagnosticsLogger.shared.log(
                "Recorded audio signal stats",
                metadata: [
                    "file": fileURL.path,
                    "peak": String(audioStats.peak),
                    "rms": String(format: "%.2f", audioStats.rms)
                ]
            )

            if audioStats.peak == 0 {
                DiagnosticsLogger.shared.log(
                    "Discarded silent audio recording",
                    metadata: ["file": fileURL.path]
                )
                throw SpeechTranscriptionError.silentAudio
            }
        }

        if let persistedURL = DiagnosticsLogger.shared.persistDebugAudio(from: fileURL) {
            DiagnosticsLogger.shared.log(
                "Persisted debug audio recording",
                metadata: ["file": persistedURL.path]
            )
        }

        guard fileSize > 0 else {
            DiagnosticsLogger.shared.log(
                "Discarded empty audio recording",
                metadata: ["file": fileURL.path]
            )
            try? FileManager.default.removeItem(at: fileURL)
            throw SpeechTranscriptionError.noSpeechDetected
        }

        return fileURL
    }

    func cancel() {
        recorder?.stop()
        recorder = nil

        if let fileURL {
            DiagnosticsLogger.shared.log(
                "Cancelled audio recording",
                metadata: ["file": fileURL.path]
            )
            try? FileManager.default.removeItem(at: fileURL)
        }

        fileURL = nil
    }

    private func audioStats(forPCM16MonoWavAt fileURL: URL) -> (peak: Float, rms: Float)? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            return nil
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return nil
        }

        var peak: Float = 0
        var squareSum: Float = 0
        var sampleCount = 0

        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = samples[frameIndex]
                let magnitude = abs(sample)
                if magnitude > peak {
                    peak = magnitude
                }
                squareSum += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        return (peak: peak, rms: sqrt(squareSum / Float(sampleCount)))
    }
}

final class AppleSpeechTranscriptionService: SpeechTranscribing, @unchecked Sendable {
    var requiresSpeechRecognitionPermission: Bool { true }

    private let recorder = DictationAudioRecorder()

    func startRecording() throws {
        try recorder.start()
    }

    func stopRecordingAndTranscribe(locale: Locale) async throws -> String {
        let fileURL = try recorder.stop()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        DiagnosticsLogger.shared.log(
            "Starting Apple Speech transcription",
            metadata: [
                "file": fileURL.path,
                "locale": locale.identifier
            ]
        )

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            var recognitionTask: SFSpeechRecognitionTask?
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    recognitionTask?.cancel()
                    DiagnosticsLogger.shared.log(
                        "Apple Speech transcription failed",
                        metadata: ["error": error.localizedDescription]
                    )
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }
                recognitionTask?.cancel()
                DiagnosticsLogger.shared.log(
                    "Apple Speech transcription succeeded",
                    metadata: ["textLength": String(result.bestTranscription.formattedString.count)]
                )
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    func cancel() {
        recorder.cancel()
    }
}

final class OpenAICompatibleSpeechTranscriptionService: SpeechTranscribing, @unchecked Sendable {
    var requiresSpeechRecognitionPermission: Bool { false }

    private let configuration: OpenAICompatibleTranscriptionConfiguration
    private let session: URLSession
    private let transcriptionTimeout: TimeInterval
    private let recorder = DictationAudioRecorder()

    init(
        configuration: OpenAICompatibleTranscriptionConfiguration,
        session: URLSession = .shared,
        transcriptionTimeout: TimeInterval = 30
    ) {
        self.configuration = configuration
        self.session = session
        self.transcriptionTimeout = transcriptionTimeout
    }

    func startRecording() throws {
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedBaseURL.isEmpty else {
            throw SpeechTranscriptionError.invalidConfiguration("A transcription API base URL is required.")
        }

        guard !trimmedModel.isEmpty else {
            throw SpeechTranscriptionError.invalidConfiguration("A transcription model is required.")
        }

        if trimmedBaseURL.contains("api.groq.com"), trimmedAPIKey.isEmpty {
            throw SpeechTranscriptionError.invalidConfiguration("A Groq API key is required.")
        }

        DiagnosticsLogger.shared.log(
            "Configured OpenAI-compatible transcription backend",
            metadata: [
                "baseURL": trimmedBaseURL,
                "model": trimmedModel,
                "hasAPIKey": trimmedAPIKey.isEmpty ? "false" : "true"
            ]
        )
        try recorder.start()
    }

    func stopRecordingAndTranscribe(locale: Locale) async throws -> String {
        let fileURL = try recorder.stop()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return try await transcribe(fileURL: fileURL, locale: locale)
    }

    func cancel() {
        recorder.cancel()
    }

    private func transcribe(fileURL: URL, locale: Locale) async throws -> String {
        let languageHint = TranscriptionLanguageHint.from(locale: locale)
        let trimmedBaseURL = configuration.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let boundary = UUID().uuidString

        guard let url = URL(string: "\(trimmedBaseURL)/audio/transcriptions") else {
            throw SpeechTranscriptionError.invalidConfiguration("The transcription API base URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let audioData = try Data(contentsOf: fileURL)
        let body = makeMultipartBody(
            audioData: audioData,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType(for: fileURL),
            model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            language: languageHint,
            boundary: boundary
        )

        DiagnosticsLogger.shared.log(
            "Submitting OpenAI-compatible transcription request",
            metadata: [
                "url": url.absoluteString,
                "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
                "locale": locale.identifier,
                "language": languageHint ?? "<none>"
            ]
        )

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            DiagnosticsLogger.shared.log("Transcription server returned no HTTP response")
            throw SpeechTranscriptionError.uploadFailed("No response from the transcription server.")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        DiagnosticsLogger.shared.log(
            "Transcription server response received",
            metadata: [
                "url": url.absoluteString,
                "status": String(httpResponse.statusCode),
                "body": String(responseBody.prefix(2000))
            ]
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpeechTranscriptionError.uploadFailed(
                "Transcription request failed with status \(httpResponse.statusCode): \(responseBody)"
            )
        }

        let transcript = try parseTranscript(from: data)
        DiagnosticsLogger.shared.log(
            "OpenAI-compatible transcription succeeded",
            metadata: ["textLength": String(transcript.count)]
        )
        return transcript
    }

    private func makeMultipartBody(
        audioData: Data,
        fileName: String,
        mimeType: String,
        model: String,
        language: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        if let language, !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }

    private func parseTranscript(from data: Data) throws -> String {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw SpeechTranscriptionError.uploadFailed("The transcription response did not contain text.")
        }

        return text
    }
}
