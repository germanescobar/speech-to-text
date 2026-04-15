import AppKit
import SwiftUI

@MainActor
final class FloatingStatusPanelController {
    private let viewModel = FloatingStatusViewModel()
    private var shouldPersistUntilDismissed = false
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(
            rootView: FloatingStatusView(
                viewModel: viewModel,
                onClose: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.hide()
                    }
                }
            )
        )
        return panel
    }()

    var audioLevelProvider: (() -> Float)? {
        get { viewModel.audioLevelProvider }
        set { viewModel.audioLevelProvider = newValue }
    }

    func update(with state: DictationSessionState) {
        viewModel.state = state
        shouldPersistUntilDismissed = (state.phase == .failed)

        switch state.phase {
        case .idle:
            hide()
        case .requestingPermissions, .listening, .processing, .completed, .failed:
            show()
        }
    }

    func hide() {
        shouldPersistUntilDismissed = false
        panel.orderOut(nil)
    }

    var isPersistingUntilDismissed: Bool {
        shouldPersistUntilDismissed
    }

    private func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = CGPoint(
            x: visibleFrame.maxX - panelSize.width - 20,
            y: visibleFrame.maxY - panelSize.height - 20
        )

        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class FloatingStatusViewModel: ObservableObject {
    @Published var state: DictationSessionState = .idle
    var audioLevelProvider: (() -> Float)?
}
