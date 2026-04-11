import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var shortcut: HotkeyShortcut
    @Published var autoPasteEnabled: Bool
    @Published var historyLimit: Int
    @Published var hasCompletedOnboarding: Bool

    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let shortcut = "settings.shortcut"
        static let autoPasteEnabled = "settings.autoPasteEnabled"
        static let historyLimit = "settings.historyLimit"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
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
    }
}
