@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import Dispatch

protocol SpeechTranscribing: AnyObject, Sendable {
    func startTranscribing(
        locale: Locale,
        onPartialResult: @escaping @Sendable (String) -> Void
    ) throws
    func stopTranscribing() async throws -> String
    func cancel()
}

enum SpeechTranscriptionError: LocalizedError {
    case recognizerUnavailable
    case audioEngineFailure
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable right now."
        case .audioEngineFailure:
            return "The microphone could not be started."
        case .noSpeechDetected:
            return "No speech was detected."
        }
    }
}

private struct RecognitionEvent: Sendable {
    let text: String?
    let isFinal: Bool
    let errorDescription: String?
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

final class LiveSpeechTranscriptionService: SpeechTranscribing, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopContinuation: CheckedContinuation<String, Error>?
    private var latestTranscript = ""
    private var hasActiveSession = false
    private var finishingRequested = false

    func startTranscribing(
        locale: Locale,
        onPartialResult: @escaping @Sendable (String) -> Void
    ) throws {
        cancel()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechTranscriptionError.audioEngineFailure
        }

        recognitionRequest = request
        latestTranscript = ""
        hasActiveSession = true
        finishingRequested = false

        let serviceBox = UncheckedSendableBox(self)
        let recognitionHandler: (SFSpeechRecognitionResult?, Error?) -> Void = { result, error in
            let event = RecognitionEvent(
                text: result?.bestTranscription.formattedString,
                isFinal: result?.isFinal ?? false,
                errorDescription: error?.localizedDescription
            )

            DispatchQueue.main.async { [serviceBox, event] in
                let service = serviceBox.value

                if let text = event.text {
                    service.latestTranscript = text
                    onPartialResult(text)

                    if event.isFinal {
                        service.finishStopIfNeeded(with: text)
                    }
                }

                if let errorDescription = event.errorDescription {
                    if service.finishingRequested, !service.latestTranscript.isEmpty {
                        service.finishStopIfNeeded(with: service.latestTranscript)
                    } else {
                        let error = NSError(
                            domain: "SpeechToText.SpeechRecognition",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: errorDescription]
                        )
                        service.finishStopIfNeeded(error: error)
                    }
                }
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: recognitionHandler)
    }

    func stopTranscribing() async throws -> String {
        guard hasActiveSession else {
            throw SpeechTranscriptionError.noSpeechDetected
        }

        finishingRequested = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation

            let serviceBox = UncheckedSendableBox(self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [serviceBox] in
                let service = serviceBox.value
                guard service.stopContinuation != nil else { return }

                if service.latestTranscript.isEmpty {
                    service.finishStopIfNeeded(error: SpeechTranscriptionError.noSpeechDetected)
                } else {
                    service.finishStopIfNeeded(with: service.latestTranscript)
                }
            }
        }
    }

    func cancel() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        latestTranscript = ""
        hasActiveSession = false
        finishingRequested = false

        if let stopContinuation {
            self.stopContinuation = nil
            stopContinuation.resume(throwing: SpeechTranscriptionError.noSpeechDetected)
        }
    }

    private func finishStopIfNeeded(with text: String) {
        guard let stopContinuation else { return }
        self.stopContinuation = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        hasActiveSession = false
        finishingRequested = false
        stopContinuation.resume(returning: text)
    }

    private func finishStopIfNeeded(error: Error) {
        guard let stopContinuation else { return }
        self.stopContinuation = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        hasActiveSession = false
        finishingRequested = false
        stopContinuation.resume(throwing: error)
    }
}
