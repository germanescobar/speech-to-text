import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var shortcut: HotkeyShortcut
    @Published var autoPasteEnabled: Bool
    @Published var historyLimit: Int
    @Published var hasCompletedOnboarding: Bool
    @Published var transcriptionProvider: TranscriptionProvider
    @Published var transcriptionAPIKey: String
    @Published var transcriptionBaseURL: String
    @Published var transcriptionModel: String

    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let shortcut = "settings.shortcut"
        static let autoPasteEnabled = "settings.autoPasteEnabled"
        static let historyLimit = "settings.historyLimit"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let transcriptionProvider = "settings.transcriptionProvider"
        static let transcriptionAPIKey = "settings.transcriptionAPIKey"
        static let transcriptionBaseURL = "settings.transcriptionBaseURL"
        static let transcriptionModel = "settings.transcriptionModel"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if
            let data = userDefaults.data(forKey: Keys.shortcut),
            let storedShortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data)
        {
            shortcut = storedShortcut
        } else {
            shortcut = .default
        }

        let storedHistoryLimit = userDefaults.object(forKey: Keys.historyLimit) as? Int
        autoPasteEnabled = userDefaults.bool(forKey: Keys.autoPasteEnabled)
        historyLimit = max(1, storedHistoryLimit ?? 20)
        hasCompletedOnboarding = userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
        let storedProvider = TranscriptionProvider(
            rawValue: userDefaults.string(forKey: Keys.transcriptionProvider) ?? ""
        ) ?? .appleSpeech
        transcriptionProvider = storedProvider
        transcriptionAPIKey = userDefaults.string(forKey: Keys.transcriptionAPIKey) ?? ""
        transcriptionBaseURL = userDefaults.string(forKey: Keys.transcriptionBaseURL)
            ?? storedProvider.defaultBaseURL
        transcriptionModel = userDefaults.string(forKey: Keys.transcriptionModel)
            ?? storedProvider.defaultModel

        bindPersistence()
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    private func bindPersistence() {
        $shortcut
            .sink { [weak self] shortcut in
                guard let self else { return }
                let data = try? JSONEncoder().encode(shortcut)
                self.userDefaults.set(data, forKey: Keys.shortcut)
            }
            .store(in: &cancellables)

        $autoPasteEnabled
            .sink { [weak self] isEnabled in
                self?.userDefaults.set(isEnabled, forKey: Keys.autoPasteEnabled)
            }
            .store(in: &cancellables)

        $historyLimit
            .sink { [weak self] limit in
                self?.userDefaults.set(max(1, limit), forKey: Keys.historyLimit)
            }
            .store(in: &cancellables)

        $hasCompletedOnboarding
            .sink { [weak self] hasCompleted in
                self?.userDefaults.set(hasCompleted, forKey: Keys.hasCompletedOnboarding)
            }
            .store(in: &cancellables)

        $transcriptionProvider
            .sink { [weak self] provider in
                self?.userDefaults.set(provider.rawValue, forKey: Keys.transcriptionProvider)
            }
            .store(in: &cancellables)

        $transcriptionAPIKey
            .sink { [weak self] apiKey in
                self?.userDefaults.set(apiKey, forKey: Keys.transcriptionAPIKey)
            }
            .store(in: &cancellables)

        $transcriptionBaseURL
            .sink { [weak self] baseURL in
                self?.userDefaults.set(baseURL, forKey: Keys.transcriptionBaseURL)
            }
            .store(in: &cancellables)

        $transcriptionModel
            .sink { [weak self] model in
                self?.userDefaults.set(model, forKey: Keys.transcriptionModel)
            }
            .store(in: &cancellables)
    }
}
