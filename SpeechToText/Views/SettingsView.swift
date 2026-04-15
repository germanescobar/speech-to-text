import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !controller.hasCompletedOnboarding {
                    onboardingCard
                }

                dictationSection
                permissionsSection
                diagnosticsSection
                historySection
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 560)
        .onAppear {
            controller.refreshPermissionSnapshot()
        }
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome")
                .font(.title2.weight(.semibold))
            Text("SpeechToText runs from the menu bar, listens when you press your shortcut, copies the final transcript to the clipboard, and can optionally paste it back into the app you were using.")
                .foregroundStyle(.secondary)
            Text("Permissions")
                .font(.headline)
            Text("Microphone is always required. Speech Recognition is only required when you use the Apple Speech provider. Accessibility is only needed if you want auto-paste into the previously focused app.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Request Microphone & Speech") {
                    controller.requestDictationPermissions()
                }
                .buttonStyle(.bordered)

                Button("Open Accessibility Settings") {
                    controller.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)

                Button("Continue") {
                    controller.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var dictationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dictation")
                .font(.headline)

            Picker("Transcription Provider", selection: Binding(
                get: { controller.transcriptionProvider },
                set: { controller.setTranscriptionProvider($0) }
            )) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            Text(controller.transcriptionProvider.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if controller.transcriptionProvider != .appleSpeech {
                VStack(alignment: .leading, spacing: 10) {
                    if controller.transcriptionProvider.requiresAPIKey {
                        SecureField("API Key", text: Binding(
                            get: { controller.transcriptionAPIKey },
                            set: { controller.setTranscriptionAPIKey($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    TextField("Base URL", text: Binding(
                        get: { controller.transcriptionBaseURL },
                        set: { controller.setTranscriptionBaseURL($0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("Model", text: Binding(
                        get: { controller.transcriptionModel },
                        set: { controller.setTranscriptionModel($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            ShortcutRecorderView(shortcut: controller.shortcut) { shortcut in
                controller.updateShortcut(shortcut)
            }

            Toggle("Enable auto-paste after dictation", isOn: Binding(
                get: { controller.autoPasteEnabled },
                set: { controller.setAutoPasteEnabled($0) }
            ))

            Text("Auto-paste uses macOS Accessibility permissions. If access is missing, dictation still succeeds and the text stays on your clipboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if controller.transcriptionProvider != .appleSpeech {
                Text("Groq and local OpenAI-compatible backends record audio first, then transcribe when you release the shortcut, so they do not show live partial text yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Apple Speech now follows the same record-then-transcribe flow as the other providers for a simpler, consistent pipeline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Launch at login is deferred for this first version.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)

            PermissionRow(title: "Microphone", status: controller.permissionSnapshot.microphone)
            PermissionRow(title: "Speech Recognition", status: controller.permissionSnapshot.speechRecognition)
            PermissionRow(title: "Accessibility", status: controller.permissionSnapshot.accessibility)

            HStack {
                Button("Request Microphone & Speech") {
                    controller.requestDictationPermissions()
                }
                .buttonStyle(.bordered)

                Button("Refresh Status") {
                    controller.refreshPermissionSnapshot()
                }
                .buttonStyle(.bordered)

                Button("Request Accessibility") {
                    controller.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent History")
                .font(.headline)

            Text("SpeechToText keeps the last \(controller.historyLimit) local transcripts on this Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { controller.historyLimit },
                    set: { controller.setHistoryLimit($0) }
                ),
                in: 1...50
            ) {
                Text("Keep \(controller.historyLimit) items")
            }

            Button("Clear History") {
                controller.clearHistory()
            }
            .buttonStyle(.bordered)
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.headline)

            Text("If Groq or another provider fails, the app now writes a log file we can inspect.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(controller.diagnosticsLogPath)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
