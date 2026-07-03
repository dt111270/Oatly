//
//  OatlyWatchApp.swift
//  OatlyWatch Watch App
//

import SwiftUI

@main
struct OatlyWatch_Watch_AppApp: App {
    @StateObject private var store = WatchTaskStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
