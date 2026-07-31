import HypeCore
import SwiftUI

struct ScriptDebuggerStepControls: View {
    var isPaused: Bool
    var showsLabels = true
    var controlSize: ControlSize = .regular
    var foregroundColor: Color = .primary
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            if showsLabels {
                Button {
                    continueExecution()
                } label: {
                    Label("Continue", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Continue script execution")
            } else {
                Button {
                    continueExecution()
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Continue script execution")
            }

            if showsLabels {
                Button {
                    stepOver()
                } label: {
                    Label("Step Over", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.bordered)
                .help("Step over calls and pause at the next statement in this handler")
            } else {
                Button {
                    stepOver()
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(foregroundColor)
                .help("Step over calls and pause at the next statement in this handler")
            }

            if showsLabels {
                Button {
                    stepInto()
                } label: {
                    Label("Step Into", systemImage: "arrow.down.right.circle")
                }
                .buttonStyle(.bordered)
                .help("Step into calls and pause at the next statement or handler")
            } else {
                Button {
                    stepInto()
                } label: {
                    Image(systemName: "arrow.down.right.circle")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(foregroundColor)
                .help("Step into calls and pause at the next statement or handler")
            }
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
