import SwiftUI

struct AudioWaveformView: View {
    let audioLevelProvider: () -> Float

    private let barCount = 20
    private let updateInterval: TimeInterval = 1.0 / 15.0

    @State private var levels: [Float] = Array(repeating: 0, count: 20)

    var body: some View {
        TimelineView(.periodic(from: .now, by: updateInterval)) { _ in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: levels[index]))
                        .frame(width: 3, height: barHeight(for: levels[index]))
                }
            }
            .frame(height: 24)
            .onChange(of: Date.now.timeIntervalSinceReferenceDate) { _, _ in
                shiftAndSample()
            }
            .onAppear {
                shiftAndSample()
            }
        }
    }

    private func shiftAndSample() {
        var newLevels = levels
        newLevels.removeFirst()
        newLevels.append(audioLevelProvider())
        withAnimation(.linear(duration: updateInterval)) {
            levels = newLevels
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minHeight: CGFloat = 2
        let maxHeight: CGFloat = 24
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }

    private func barColor(for level: Float) -> Color {
        if level > 0.6 {
            return .red.opacity(0.9)
        } else if level > 0.3 {
            return .orange.opacity(0.8)
        } else {
            return .green.opacity(0.7)
        }
    }
}
