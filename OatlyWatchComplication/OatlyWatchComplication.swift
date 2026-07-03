//
//  OatlyWatchComplication.swift
//  OatlyWatchComplication
//
//  Circular watch face complication showing the current hot task count.
//  Reads from the shared App Group that the watch app writes to.
//

import WidgetKit
import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

// MARK: - Shared identifiers

private enum SharedStore {
    static let appGroup = "group.davidturnbull.oatly.watch"
    static let hotCountKey = "oatly.hotCount"
}

// MARK: - Timeline entry

struct HotCountEntry: TimelineEntry {
    let date: Date
    let count: Int
}

// MARK: - Provider

struct Provider: TimelineProvider {
    private func currentCount() -> Int {
        guard let defaults = UserDefaults(suiteName: SharedStore.appGroup) else { return 0 }
        return defaults.integer(forKey: SharedStore.hotCountKey)
    }

    func placeholder(in context: Context) -> HotCountEntry {
        HotCountEntry(date: Date(), count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (HotCountEntry) -> Void) {
        completion(HotCountEntry(date: Date(), count: currentCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HotCountEntry>) -> Void) {
        // The watch app calls WidgetCenter.shared.reloadAllTimelines() whenever
        // a new payload arrives over WatchConnectivity, so a single entry that
        // never expires on its own is fine — we just refresh on demand.
        let entry = HotCountEntry(date: Date(), count: currentCount())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - View

struct OatlyCircularView: View {
    let count: Int

    var body: some View {
        ZStack {
            // Brand-coloured background ring/circle gives it the "Oatly backdrop" look.
            Circle()
                .fill(brandBlue.opacity(0.25))
            Circle()
                .stroke(brandBlue, lineWidth: 2)

            VStack(spacing: -2) {
                Text("🔥")
                    .font(.system(size: 10))
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }
}

struct OatlyWatchComplicationEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        OatlyCircularView(count: entry.count)
    }
}

// MARK: - Widget

struct OatlyWatchComplication: Widget {
    let kind: String = "OatlyWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OatlyWatchComplicationEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Hot tasks")
        .description("Number of hot tasks in Oatly.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    OatlyWatchComplication()
} timeline: {
    HotCountEntry(date: .now, count: 0)
    HotCountEntry(date: .now, count: 4)
    HotCountEntry(date: .now, count: 12)
}
