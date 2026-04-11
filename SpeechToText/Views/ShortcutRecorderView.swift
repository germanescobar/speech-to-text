import SwiftUI

struct ShortcutRecorderView: View {
    let shortcut: HotkeyShortcut
    let onShortcutChange: (HotkeyShortcut) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )

            Button(isRecording ? "Press Shortcut…" : "Record Shortcut") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let shortcut = HotkeyShortcut.from(event: event) else {
                return event
            }

            onShortcutChange(shortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
