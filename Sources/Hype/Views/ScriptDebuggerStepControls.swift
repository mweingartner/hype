import HypeCore
import SwiftUI

struct ScriptDebuggerStepControls: View {
    var isPaused: Bool
    var showsLabels = true
    var controlSize: ControlSize = .regular
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Button {
                continueExecution()
            } label: {
                if showsLabels {
                    Label("Continue", systemImage: "play.fill")
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .help("Continue script execution")

            Button {
                stepOver()
            } label: {
                if showsLabels {
                    Label("Step Over", systemImage: "arrow.turn.down.right")
                } else {
                    Image(systemName: "arrow.turn.down.right")
                }
            }
            .buttonStyle(.bordered)
            .help("Step over to the next handler entry")

            Button {
                stepInto()
            } label: {
                if showsLabels {
                    Label("Step Into", systemImage: "arrow.down.right.circle")
                } else {
                    Image(systemName: "arrow.down.right.circle")
                }
            }
            .buttonStyle(.bordered)
            .help("Step into the next handler entry")
        }
        .controlSize(controlSize)
        .disabled(!isPaused)
    }

    private func continueExecution() {
        _ = HypeTalkScriptTraceRecorder.shared.resumePausedExecution()
        onAction()
    }

    private func stepOver() {
        _ = HypeTalkScriptTraceRecorder.shared.stepOverPausedExecution()
        onAction()
    }

    private func stepInto() {
        _ = HypeTalkScriptTraceRecorder.shared.stepIntoPausedExecution()
        onAction()
    }
}
