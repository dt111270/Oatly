//
//  ChecklistRunnerView.swift
//  Oatly
//
//  Single-step UI for a `ChecklistSession`. Shows one step at a time —
//  Mark Done advances, Skip records ❌ and advances, Back rewinds one
//  step. Auto-dismisses the host window when the session finishes.
//
//  Step kinds rendered (phase 1):
//    • .manual      — label + optional detail, no extra UI
//    • .openURL(_)  — adds an "Open" button that fires NSWorkspace
//    • .inline(_)   — runs the closure on appear and shows the summary
//

import SwiftUI

struct ChecklistRunnerView: View {
    @StateObject private var session: ChecklistSession
    @Environment(\.dismissWindow) private var dismissWindow

    /// The window id we dismiss when the session finishes. Must match the
    /// id passed to `Window(_:id:)` in OTApp.
    let windowId: String

    init(checklist: Checklist, windowId: String) {
        _session = StateObject(wrappedValue: ChecklistSession(checklist: checklist))
        self.windowId = windowId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            if let step = session.currentStep {
                stepBody(step)
            } else {
                Text("Done.")
                    .font(.title3)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
            controls
        }
        .padding(20)
        .frame(width: 460, height: 320)
        .onAppear { session.runInlineActionIfNeeded() }
        .onChange(of: session.currentIndex) { _, _ in
            session.runInlineActionIfNeeded()
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished {
                dismissWindow(id: windowId)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(session.checklist.title)
                .font(.headline)
            Spacer()
            if session.currentStep != nil {
                Text("Step \(session.currentIndex + 1) of \(session.stepCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func stepBody(_ step: ChecklistStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.label)
                .font(.title3)
                .fontWeight(.semibold)
            if let detail = step.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionUI(for: step)
        }
    }

    @ViewBuilder
    private func actionUI(for step: ChecklistStep) -> some View {
        switch step.action {
        case .manual:
            EmptyView()

        case .openURL(let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .padding(.top, 4)

        case .inline:
            if let result = session.inlineResult {
                ScrollView {
                    Text(result.summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 140)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Back") { session.goBack() }
                .disabled(!session.canGoBack)
            Spacer()
            Button("Skip") { session.skip() }
            Button("Mark done") { session.markDone() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }
}
