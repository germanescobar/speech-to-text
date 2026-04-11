import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var recent: [RecentTranscript]

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "history.recent") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if
            let data = userDefaults.data(forKey: storageKey),
            let transcripts = try? JSONDecoder().decode([RecentTranscript].self, from: data)
        {
            recent = transcripts
        } else {
            recent = []
        }
    }

    func add(text: String, limit: Int) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        recent.insert(RecentTranscript(text: normalizedText), at: 0)
        recent = Array(recent.prefix(max(1, limit)))
        persist()
    }

    func clear() {
        recent = []
        persist()
    }

    private func persist() {
        let data = try? JSONEncoder().encode(recent)
        userDefaults.set(data, forKey: storageKey)
    }
}
