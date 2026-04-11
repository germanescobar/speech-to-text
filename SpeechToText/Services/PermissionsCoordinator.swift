import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import Speech

struct PermissionsSnapshot {
    var microphone: String
    var speechRecognition: String
    var accessibility: String
}

class PermissionsCoordinator: @unchecked Sendable {
    func requestMicrophoneIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await Self.requestMicrophoneAccess()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func requestSpeechRecognitionIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await Self.requestSpeechAuthorization()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let trusted = AXIsProcessTrusted()

        if prompt, !trusted {
            openAccessibilitySettings()
        }

        return trusted
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openSpeechRecognitionSettings() {
        openPrivacySettings(anchor: "Privacy_SpeechRecognition")
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func currentSnapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: description(for: AVCaptureDevice.authorizationStatus(for: .audio)),
            speechRecognition: description(for: SFSpeechRecognizer.authorizationStatus()),
            accessibility: isAccessibilityTrusted(prompt: false) ? "Granted" : "Not granted"
        )
    }

    private func description(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func description(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    nonisolated private static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
