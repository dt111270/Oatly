//
//  SmartFilter.swift
//  Oatly
//
//  Created by David Turnbull on 29/04/2026.
//


import Foundation

enum SmartFilter: String, CaseIterable, Hashable {
    case hot     = "Hot"
    case overdue = "Overdue"
    case warm    = "Warm"
    case cool    = "Cool"
    case log     = "Log"

    var label: String {
        switch self {
        case .hot:     return "🔥 Hot"
        case .overdue: return "🧯 Overdue"
        case .warm:    return "⛅ Warm"
        case .cool:    return "❄️ Cool"
        case .log:     return "✅ Log"
        }
    }
}