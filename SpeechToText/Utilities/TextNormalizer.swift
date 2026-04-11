import Foundation

enum TextNormalizer {
    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let collapsedWhitespace = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
