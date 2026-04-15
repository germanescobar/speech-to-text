import Foundation

final class DiagnosticsLogger: @unchecked Sendable {
    static let shared = DiagnosticsLogger()

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let queue = DispatchQueue(label: "SpeechToText.DiagnosticsLogger")

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.sortedKeys]
    }

    var logFileURL: URL {
        supportDirectory.appendingPathComponent("diagnostics.log")
    }

    var supportDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("SpeechToText", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func log(_ message: String, metadata: [String: String] = [:]) {
        queue.async {
            let event = LogEvent(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                message: message,
                metadata: metadata
            )

            guard let data = try? self.encoder.encode(event) else { return }
            guard let line = String(data: data, encoding: .utf8)?.appending("\n") else { return }

            if !self.fileManager.fileExists(atPath: self.logFileURL.path) {
                self.fileManager.createFile(atPath: self.logFileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: self.logFileURL) else { return }
            defer { try? handle.close() }

            do {
                try handle.seekToEnd()
                handle.write(Data(line.utf8))
            } catch {
                return
            }
        }
    }

    func persistDebugAudio(from sourceURL: URL) -> URL? {
        let destinationURL = supportDirectory.appendingPathComponent("last-recording.\(sourceURL.pathExtension)")

        queue.sync {
            try? fileManager.removeItem(at: destinationURL)
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                return
            }
        }

        return destinationURL
    }
}

private struct LogEvent: Codable {
    let timestamp: String
    let message: String
    let metadata: [String: String]
}
