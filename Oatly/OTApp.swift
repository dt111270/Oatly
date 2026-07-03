//
//  OTApp.swift
//  OT
//
//  Created by David Turnbull on 28/04/2026.
//

import SwiftUI
import Sparkle

@main
struct OTApp: App {
    /// Sparkle. `startingUpdater: true` kicks off the background updater on
    /// launch; with the Info.plist auto-update keys set, it checks and installs
    /// new versions silently. Held for the app's lifetime.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandMenu("Routines") {
                OpenChecklistButton(
                    title: "Morning Check-In",
                    windowId: "checklist.morning-check-in",
                    shortcut: KeyboardShortcut("m", modifiers: [.command, .shift])
                )
                OpenChecklistButton(
                    title: "Evening Check-Out",
                    windowId: "checklist.evening-check-out",
                    shortcut: KeyboardShortcut("e", modifiers: [.command, .shift])
                )
                OpenChecklistButton(
                    title: "Weekly Task Review",
                    windowId: "checklist.weekly-task-review",
                    shortcut: KeyboardShortcut("r", modifiers: [.command, .shift])
                )
            }
        }

        // Floating checklist windows. One Window per checklist — single
        // instance, brought to front by openWindow(id:) if already open.
        Window("Morning Check-In", id: "checklist.morning-check-in") {
            ChecklistRunnerView(
                checklist: MorningCheckIn.checklist,
                windowId: "checklist.morning-check-in"
            )
        }
        .windowResizability(.contentSize)

        Window("Evening Check-Out", id: "checklist.evening-check-out") {
            ChecklistRunnerView(
                checklist: EveningCheckOut.checklist,
                windowId: "checklist.evening-check-out"
            )
        }
        .windowResizability(.contentSize)

        Window("Weekly Task Review", id: "checklist.weekly-task-review") {
            ChecklistRunnerView(
                checklist: WeeklyTaskReview.checklist,
                windowId: "checklist.weekly-task-review"
            )
        }
        .windowResizability(.contentSize)
    }
}

/// Menu-bar button that opens (or focuses) a checklist window. Lives in a
/// view body because `openWindow` is an `@Environment` value.
private struct OpenChecklistButton: View {
    let title: String
    let windowId: String
    let shortcut: KeyboardShortcut

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            openWindow(id: windowId)
        }
        .keyboardShortcut(shortcut)
    }
}
