import SwiftUI

struct FloatingStatusView: View {
    @ObservedObject var viewModel: FloatingStatusViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(titleText)
                    .font(.headline)
                Spacer()
                if viewModel.state.phase == .listening {
                    elapsedTimeView
                }
                if viewModel.state.phase == .failed {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let message = viewModel.state.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        )
        .padding(8)
    }

    @ViewBuilder
    private var elapsedTimeView: some View {
        if let startedAt = viewModel.state.startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                Text(Self.elapsedTimeString(from: startedAt, to: timeline.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleText: String {
        switch viewModel.state.phase {
        case .idle:
            return "Idle"
        case .requestingPermissions:
            return "Checking Access"
        case .listening:
            return "Recording"
        case .processing:
            return "Processing"
        case .completed:
            return "Ready"
        case .failed:
            return "Something Went Wrong"
        }
    }

    private var bodyText: String {
        switch viewModel.state.phase {
        case .listening:
            return "Speak naturally and press the shortcut again when you’re done."
        case .processing:
            return "SpeechToText is transcribing your recording."
        case .completed:
            return viewModel.state.finalTranscript
        case .failed:
            if let message = viewModel.state.message,
               message.contains("appears to be silent") {
                return "No usable audio was detected. Check your macOS audio input device and try again."
            }
            return viewModel.state.message ?? "The last dictation could not be completed."
        case .requestingPermissions:
            return "SpeechToText is requesting the permissions needed to begin dictation."
        case .idle:
            return "Press your shortcut to start dictating."
        }
    }

    private var statusColor: Color {
        switch viewModel.state.phase {
        case .idle:
            return .gray
        case .requestingPermissions, .processing:
            return .orange
        case .listening:
            return .red
        case .completed:
            return .green
        case .failed:
            return .pink
        }
    }

    private static func elapsedTimeString(from start: Date, to current: Date) -> String {
        let elapsed = Int(current.timeIntervalSince(start))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}
