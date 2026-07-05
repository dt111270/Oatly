//
//  SidebarSelection.swift
//  OT
//
//  Created by David Turnbull on 28/04/2026.
//

import Foundation

enum SidebarSelection: Hashable {
    case smart(SmartFilter)
    case role(String)
    case recurring
}

enum SmartFilter: String, CaseIterable, Hashable {
    case today   = "Today"
    case hot     = "Hot"
    case overdue = "Overdue"
    case warm    = "Warm"
    case cool    = "Cool"
    case log     = "Log"

    var label: String {
        switch self {
        case .today:   return "📅 Today"
        case .hot:     return "🔥 Hot"
        case .overdue: return "🧯 Overdue"
        case .warm:    return "⛅ Warm"
        case .cool:    return "❄️ Cool"
        case .log:     return "✅ Log"
        }
    }
}
