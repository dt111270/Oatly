import Foundation
import Combine
import UIKit
import WatchConnectivity

class iOSTaskStore: NSObject, ObservableObject {
    @Published var tasks: [OTTaskJSON] = []
    @Published var checkedNames: Set<String> = []

    /// Raw JSON bytes of the most recent load — kept so we can push the
    /// same payload to the watch whenever the WC session becomes active
    /// or the user opens the iPhone app.
    private var lastPayloadData: Data?

    override init() {
        super.init()
        TaskNotificationScheduler.requestAuthorizationIfNeeded()
        activateWatchSession()
        load()
    }

    // MARK: - iCloud load

    func load() {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.davidturnbull.oatly"
        ) else { return }

        let fileURL = containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent("tasks.json")

        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(OTTasksPayload.self, from: data)
        else { return }

        // Write to App Group so the widget can read it without iCloud access
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.davidturnbull.oatly"
        ) {
            try? data.write(to: groupURL.appendingPathComponent("tasks.json"))
        }

        lastPayloadData = data
        pushToWatch(data)

        TaskNotificationScheduler.sync(tasks: payload.tasks)

        DispatchQueue.main.async {
            self.tasks = payload.tasks
            let taskNames = Set(payload.tasks.map { $0.name })
            self.checkedNames = self.checkedNames.intersection(taskNames)
        }
    }

    func markDone(_ task: OTTaskJSON) {
        checkedNames.insert(task.name)
        guard let filepath = task.filepath else {
            print("No filepath for task: \(task.name)")
            return
        }
        let encoded = filepath
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filepath
        let urlString = "obsidian://adv-uri?vault=DTObs&filepath=\(encoded)&frontmatterkey=status&data=done"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Watch push

    private func activateWatchSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushToWatch(_ data: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Filter to hot tasks before sending — the watch only displays hot
        // tasks, and keeping the payload small keeps us comfortably under
        // WC's ~65 KB application context size limit.
        guard let full = try? JSONDecoder().decode(OTTasksPayload.self, from: data) else { return }
        let hotOnly = OTTasksPayload(
            updated: full.updated,
            tasks: full.tasks.filter { $0.status == "hot" }
        )
        guard let hotData = try? JSONEncoder().encode(hotOnly) else { return }

        // updateApplicationContext coalesces — only the latest snapshot
        // is delivered to the watch, which is what we want for "current
        // task list". Safe to call on every load.
        do {
            try session.updateApplicationContext(["payload": hotData])
        } catch {
            print("WCSession updateApplicationContext failed: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension iOSTaskStore: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error)")
            return
        }
        // If we already loaded tasks before the session activated, push now.
        if let data = lastPayloadData, activationState == .activated {
            pushToWatch(data)
        }
    }

    // Required stubs — iPhone may pair with a different watch during runtime.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate to support pairing with a new watch.
        WCSession.default.activate()
    }
}
