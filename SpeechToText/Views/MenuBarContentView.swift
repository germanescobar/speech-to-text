import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(controller.primaryActionTitle) {
                controller.toggleDictation()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.isBusy)

            Text("Shortcut: \(controller.shortcut.displayString)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let statusMessage = controller.statusLine {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if controller.recentHistory.isEmpty {
                Text("No recent transcripts yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(controller.recentHistory.prefix(5))) { item in
                    Button {
                        controller.copyTranscript(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .lineLimit(2)
                            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            Button("Settings…") {
                controller.showSettings()
            }

            Button("Quit") {
                controller.quit()
            }
        }
        .padding(.vertical, 6)
    }
}
