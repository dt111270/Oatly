//
//  WatchTaskStore.swift
//  OatlyWatch Watch App
//
//  Receives task data from the paired iPhone via WatchConnectivity,
//  persists the latest snapshot to UserDefaults so it survives launches
//  when the phone isn't reachable, and exposes hot tasks grouped by role.
//

import Foundation
import Combine
import WatchConnectivity
import WidgetKit

/// Shared identifiers between the watch app and the complication widget.
enum OatlyWatchSharedStore {
    static let appGroup = "group.davidturnbull.oatly.watch"
    static let hotCountKey = "oatly.hotCount"
    static let lastUpdatedKey = "oatly.lastUpdated"
}

struct WatchTaskSection: Identifiable {
    let role: String
    let tasks: [OTTaskJSON]
    var id: String { role }
}

@MainActor
final class WatchTaskStore: NSObject, ObservableObject {
    @Published var tasks: [OTTaskJSON] = []
    @Published var lastUpdated: Date?

    private let cacheKey = "oatly.tasks.cache"
    private let cacheDateKey = "oatly.tasks.cacheDate"

    override init() {
        super.init()
        loadCached()
        activateSession()
    }

    // MARK: - Session activation

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Local cache

    private func loadCached() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: cacheKey),
           let payload = try? JSONDecoder().decode(OTTasksPayload.self, from: data) {
            tasks = payload.tasks
        }
        if let date = defaults.object(forKey: cacheDateKey) as? Date {
            lastUpdated = date
        }
        // Keep the complication's App Group in sync on cold launches too,
        // in case the App Group was reset or the watch app was reinstalled
        // while the complication is still on a watch face.
        publishHotCountToAppGroup()
    }

    private func cache(_ data: Data) {
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: cacheKey)
        defaults.set(Date(), forKey: cacheDateKey)
    }

    // MARK: - Public computed views

    /// Hot tasks grouped by role, roles A→Z, tasks sorted by due date then name.
    var hotSections: [WatchTaskSection] {
        let hot = tasks.filter { $0.status == "hot" }
        let roles = Array(Set(hot.map { $0.role })).sorted()
        return roles.compactMap { role in
            let roleTasks = hot
                .filter { $0.role == role }
                .sorted {
                    let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
                    return d0 == d1 ? $0.name < $1.name : d0 < d1
                }
            return roleTasks.isEmpty ? nil : WatchTaskSection(role: role, tasks: roleTasks)
        }
    }

    // MARK: - Receive

    fileprivate func handleReceivedContext(_ context: [String: Any]) {
        guard let payloadData = context["payload"] as? Data else { return }
        guard let payload = try? JSONDecoder().decode(OTTasksPayload.self, from: payloadData) else { return }
        Task { @MainActor in
            self.tasks = payload.tasks
            self.lastUpdated = Date()
            self.cache(payloadData)
            self.publishHotCountToAppGroup()
        }
    }

    /// Writes the current hot task count to the shared App Group so the
    /// complication widget can read it, then asks WidgetKit to refresh
    /// any active complications.
    private func publishHotCountToAppGroup() {
        guard let defaults = UserDefaults(suiteName: OatlyWatchSharedStore.appGroup) else { return }
        let hotCount = tasks.filter { $0.status == "hot" }.count
        defaults.set(hotCount, forKey: OatlyWatchSharedStore.hotCountKey)
        defaults.set(Date(), forKey: OatlyWatchSharedStore.lastUpdatedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

extension WatchTaskStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error)")
            return
        }
        // If there's already a context delivered, pick it up.
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            Task { @MainActor in
                self.handleReceivedContext(context)
            }
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedContext(applicationContext)
        }
    }
}
