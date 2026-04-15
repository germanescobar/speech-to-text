import AppKit
import Combine
import Foundation

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var permissionSnapshot = PermissionsSnapshot(
        microphone: "Not requested",
        speechRecognition: "Not requested",
        accessibility: "Not granted"
    )

    let settingsStore: SettingsStore
    let historyStore: HistoryStore

    private let permissionsCoordinator: PermissionsCoordinator
    private let clipboardPasteService: ClipboardPasteService
    private let sessionManager: DictationSessionManager
    private let hotkeyManager: HotkeyManager
    private let floatingPanelController: FloatingStatusPanelController

    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var hideOverlayTask: Task<Void, Never>?
    private var targetApplication: NSRunningApplication?

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: HistoryStore = HistoryStore(),
        permissionsCoordinator: PermissionsCoordinator = PermissionsCoordinator(),
        clipboardPasteService: ClipboardPasteService = ClipboardPasteService(),
        transcriptionServiceFactory: (() -> SpeechTranscribing)? = nil
    ) {
        let resolvedTranscriptionFactory = transcriptionServiceFactory ?? {
            AppController.makeTranscriptionService(settingsStore: settingsStore)
        }

        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.permissionsCoordinator = permissionsCoordinator
        self.clipboardPasteService = clipboardPasteService
        self.hotkeyManager = HotkeyManager()
        self.floatingPanelController = FloatingStatusPanelController()
        self.sessionManager = DictationSessionManager(
            permissionsCoordinator: permissionsCoordinator,
            transcriptionServiceFactory: resolvedTranscriptionFactory
        )

        bindState()
        refreshPermissionSnapshot()
        registerHotkey()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.presentOnboardingIfNeeded()
        }
    }

    var shortcut: HotkeyShortcut { settingsStore.shortcut }
    var autoPasteEnabled: Bool { settingsStore.autoPasteEnabled }
    var historyLimit: Int { settingsStore.historyLimit }
    var hasCompletedOnboarding: Bool { settingsStore.hasCompletedOnboarding }
    var transcriptionProvider: TranscriptionProvider { settingsStore.transcriptionProvider }
    var transcriptionAPIKey: String { settingsStore.transcriptionAPIKey }
    var transcriptionBaseURL: String { settingsStore.transcriptionBaseURL }
    var transcriptionModel: String { settingsStore.transcriptionModel }
    var recentHistory: [RecentTranscript] { historyStore.recent }
    var menuBarIconName: String { isListening ? "waveform.circle.fill" : "waveform.circle" }
    var diagnosticsLogPath: String { DiagnosticsLogger.shared.logFileURL.path }

    var isListening: Bool {
        sessionManager.state.phase == .listening
    }

    var isBusy: Bool {
        switch sessionManager.state.phase {
        case .requestingPermissions, .processing:
            return true
        case .idle, .listening, .completed, .failed:
            return false
        }
    }

    var primaryActionTitle: String {
        switch sessionManager.state.phase {
        case .listening:
            return "Stop Dictation"
        case .requestingPermissions:
            return "Requesting Permissions…"
        case .processing:
            return "Processing…"
        case .idle, .completed, .failed:
            return "Start Dictation"
        }
    }

    var statusLine: String? {
        switch sessionManager.state.phase {
        case .idle:
            return nil
        case .listening:
            return "Recording now"
        case .requestingPermissions, .processing, .completed, .failed:
            return sessionManager.state.message
        }
    }

    func toggleDictation() {
        hideOverlayTask?.cancel()

        switch sessionManager.state.phase {
        case .idle, .completed, .failed:
            Task { @MainActor in
                await startDictation()
            }
        case .listening:
            Task { @MainActor in
                await stopDictation()
            }
        case .requestingPermissions, .processing:
            break
        }
    }

    func updateShortcut(_ shortcut: HotkeyShortcut) {
        settingsStore.shortcut = shortcut
    }

    func setAutoPasteEnabled(_ isEnabled: Bool) {
        settingsStore.autoPasteEnabled = isEnabled
        refreshPermissionSnapshot()
    }

    func setHistoryLimit(_ limit: Int) {
        settingsStore.historyLimit = max(1, limit)
    }

    func setTranscriptionProvider(_ provider: TranscriptionProvider) {
        let previousProvider = settingsStore.transcriptionProvider
        settingsStore.transcriptionProvider = provider

        guard provider != previousProvider else { return }

        settingsStore.transcriptionBaseURL = provider.defaultBaseURL
        settingsStore.transcriptionModel = provider.defaultModel
        refreshPermissionSnapshot()
    }

    func setTranscriptionAPIKey(_ apiKey: String) {
        settingsStore.transcriptionAPIKey = apiKey
    }

    func setTranscriptionBaseURL(_ baseURL: String) {
        settingsStore.transcriptionBaseURL = baseURL
    }

    func setTranscriptionModel(_ model: String) {
        settingsStore.transcriptionModel = model
    }

    func clearHistory() {
        historyStore.clear()
    }

    func copyTranscript(_ transcript: RecentTranscript) {
        clipboardPasteService.copy(text: transcript.text)
        sessionManager.setCompletionMessage("Copied transcript from history.")
        floatingPanelController.update(with: .completed(text: transcript.text, message: "Copied transcript from history."))
        scheduleOverlayHide()
    }

    func showSettings() {
        settingsWindowController?.show()
    }

    func completeOnboarding() {
        settingsStore.markOnboardingCompleted()
        showSettings()
    }

    func refreshPermissionSnapshot() {
        permissionSnapshot = permissionsCoordinator.currentSnapshot()
    }

    func requestAccessibilityPermission() {
        _ = permissionsCoordinator.isAccessibilityTrusted(prompt: true)
        refreshPermissionSnapshot()
    }

    func requestDictationPermissions() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let microphoneGranted = await self.permissionsCoordinator.requestMicrophoneIfNeeded()
            let requiresSpeechRecognition = self.settingsStore.transcriptionProvider.requiresSpeechRecognitionPermission
            let speechGranted = requiresSpeechRecognition
                ? await self.permissionsCoordinator.requestSpeechRecognitionIfNeeded()
                : true

            if !microphoneGranted {
                self.permissionsCoordinator.openMicrophoneSettings()
            }

            if requiresSpeechRecognition && !speechGranted {
                self.permissionsCoordinator.openSpeechRecognitionSettings()
            }

            self.refreshPermissionSnapshot()
        }
    }

    func quit() {
        sessionManager.cancel()
        hotkeyManager.unregister()
        NSApp.terminate(nil)
    }

    private func bindState() {
        settingsWindowController = SettingsWindowController(controller: self)

        sessionManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.objectWillChange.send()
                    self.floatingPanelController.update(with: state)

                    if state.phase == .failed {
                        self.scheduleOverlayHide()
                    }
                }
            }
            .store(in: &cancellables)

        settingsStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.registerHotkey()
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        historyStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    private func registerHotkey() {
        hotkeyManager.register(shortcut: settingsStore.shortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleDictation()
            }
        }
    }

    private func startDictation() async {
        targetApplication = activeTargetApplication()
        DiagnosticsLogger.shared.log(
            "Starting dictation session",
            metadata: [
                "provider": settingsStore.transcriptionProvider.rawValue,
                "baseURL": settingsStore.transcriptionBaseURL,
                "model": settingsStore.transcriptionModel
            ]
        )
        await sessionManager.start()

        if sessionManager.state.phase == .failed {
            DiagnosticsLogger.shared.log(
                "Dictation failed to start",
                metadata: ["message": sessionManager.state.message ?? "Unknown error"]
            )
            scheduleOverlayHide(after: 5)
        }
    }

    private func stopDictation() async {
        guard let transcript = await sessionManager.stop() else {
            DiagnosticsLogger.shared.log(
                "Dictation stopped without transcript",
                metadata: ["message": sessionManager.state.message ?? "No message"]
            )
            if !floatingPanelController.isPersistingUntilDismissed {
                scheduleOverlayHide(after: 5)
            }
            return
        }

        clipboardPasteService.copy(text: transcript)
        historyStore.add(text: transcript, limit: settingsStore.historyLimit)
        DiagnosticsLogger.shared.log(
            "Dictation transcript stored",
            metadata: [
                "textLength": String(transcript.count),
                "historyCount": String(historyStore.recent.count),
                "preview": String(transcript.prefix(120))
            ]
        )

        var completionMessage = "Copied to clipboard."

        if settingsStore.autoPasteEnabled {
            let pasted = await clipboardPasteService.pasteInto(targetApplication)
            completionMessage = pasted
                ? "Copied to clipboard and pasted into the active app."
                : "Copied to clipboard; auto-paste unavailable."
        }

        sessionManager.setCompletionMessage(completionMessage)
        refreshPermissionSnapshot()
        scheduleOverlayHide()
    }

    private func scheduleOverlayHide(after seconds: Double = 2.4) {
        if floatingPanelController.isPersistingUntilDismissed {
            return
        }
        hideOverlayTask?.cancel()
        hideOverlayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.sessionManager.cancel()
        }
    }

    private func presentOnboardingIfNeeded() {
        guard !settingsStore.hasCompletedOnboarding else {
            return
        }

        showSettings()
    }

    private func activeTargetApplication() -> NSRunningApplication? {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.frontmostApplication
            .flatMap { app in
                guard app.bundleIdentifier != currentBundleIdentifier else {
                    return nil
                }
                return app
            }
    }

    private static func makeTranscriptionService(settingsStore: SettingsStore) -> SpeechTranscribing {
        switch settingsStore.transcriptionProvider {
        case .appleSpeech:
            return AppleSpeechTranscriptionService()
        case .groq, .localOpenAICompatible:
            return OpenAICompatibleSpeechTranscriptionService(
                configuration: OpenAICompatibleTranscriptionConfiguration(
                    baseURL: settingsStore.transcriptionBaseURL,
                    apiKey: settingsStore.transcriptionAPIKey,
                    model: settingsStore.transcriptionModel
                )
            )
        }
    }
}
