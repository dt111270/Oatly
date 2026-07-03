//
//  OatlyMobileApp.swift
//  OatlyMobile
//
//  Created by David Turnbull on 29/04/2026.
//

import SwiftUI
import UIKit

@main
struct OatlyMobileApp: App {
    var body: some Scene {
        WindowGroup {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadContentView()
            } else {
                ContentView()
            }
        }
    }
}
