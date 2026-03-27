//
//  SessionStatus.swift
//  PlayerPath
//
//  Status enum for coach instruction sessions.
//

import SwiftUI

enum SessionStatus: String, Codable, Hashable {
    case scheduled
    case live
    case reviewing
    case completed

    var displayText: String {
        switch self {
        case .scheduled: return "SCHEDULED"
        case .live: return "LIVE"
        case .reviewing: return "REVIEW"
        case .completed: return "DONE"
        }
    }

    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .live: return .red
        case .reviewing: return .orange
        case .completed: return .green
        }
    }

    var icon: String {
        switch self {
        case .scheduled: return "calendar.badge.clock"
        case .live: return "record.circle"
        case .reviewing: return "eye"
        case .completed: return "checkmark.circle"
        }
    }

    var isActive: Bool { self == .live || self == .reviewing }
}
