//
//  UploadStatusFilter.swift
//  PlayerPath
//
//  Hosts VideoLibraryFilter — the pill-row filter for the Videos tab.
//  Filename kept for diff continuity; the enum was renamed from UploadStatusFilter
//  when upload-state filters were retired in favor of role-based filtering.
//

import SwiftUI

enum VideoLibraryFilter: String, CaseIterable {
    case all = "All Videos"
    case untagged = "Untagged"
    case batter = "Batter"
    case pitcher = "Pitcher"

    var icon: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .untagged: return "tag.slash"
        case .batter:   return "figure.baseball"
        case .pitcher:  return "figure.cricket"
        }
    }

    var color: Color {
        switch self {
        case .all:              return .primary
        case .untagged:         return .orange
        case .batter, .pitcher: return .brandNavy
        }
    }
}
