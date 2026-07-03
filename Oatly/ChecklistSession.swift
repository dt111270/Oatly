//
//  ChecklistSession.swift
//  Oatly
//
//  One run through a `Checklist`. Owns step statuses and current-index
//  state; advances forward on done/skip, allows one-step rewind via back.
//  Finishing the last step triggers the logger and flips `isFinished`,
//  which the runner view observes to dismiss its window.
//

import Foundation
import Combine

@MainActor
final class ChecklistSession: ObservableObject {
    let checklist: Checklist
    let startedAt: Date

    @Published var stepStatuses: [StepStatus]
    @Published var currentIndex: Int = 0
    @Published var inlineResult: InlineActionResult?
    @Published var isFinished: Bool = false

    init(checklist: Checklist) {
        self.checklist = checklist
        self.startedAt = Date()
        self.stepStatuses = Array(repeating: .pending, count: checklist.steps.count)
    }

    // MARK: - Derived

    var currentStep: ChecklistStep? {
        guard currentIndex < checklist.steps.count else { return nil }
        return checklist.steps[currentIndex]
    }

    var stepCount: Int { checklist.steps.count }

    var canGoBack: Bool { currentIndex > 0 }

    // MARK: - Mutation

    func markDone() {
        guard currentIndex < stepStatuses.count else { return }
        stepStatuses[currentIndex] = .done
        advance()
    }

    func skip() {
        guard currentIndex < stepStatuses.count else { return }
        stepStatuses[currentIndex] = .skipped
        advance()
    }

    /// Rewind one step. The previous step is reset to pending so the user
    /// can re-decide. Any inline-result cached from the current step is
    /// cleared so the inline action re-fires when we land back on it.
    func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        stepStatuses[currentIndex] = .pending
        inlineResult = nil
    }

    private func advance() {
        inlineResult = nil
        if currentIndex + 1 >= checklist.steps.count {
            finish()
        } else {
            currentIndex += 1
        }
    }

    /// Called by the view in `.onAppear` and when `currentIndex` changes.
    /// Idempotent — only fires the closure if no result is cached.
    func runInlineActionIfNeeded() {
        guard let step = currentStep else { return }
        guard case .inline(let action) = step.action else { return }
        guard inlineResult == nil else { return }
        inlineResult = action.perform()
    }

    // MARK: - Finish

    private func finish() {
        do {
            try ChecklistLogger.writeLog(for: self)
        } catch {
            // Phase 1: surface via print. If this becomes a real issue,
            // promote to a published errorMessage and show in the UI.
            print("Checklist log write failed: \(error)")
        }
        isFinished = true
    }
}
