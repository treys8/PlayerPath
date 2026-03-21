//
//  UploadStatusFilter.swift
//  PlayerPath
//
//  Extracted from VideoClipsView.swift
//

import SwiftUI

enum UploadStatusFilter: String, CaseIterable {
    case all = "All Videos"
    case uploaded = "Uploaded"
    case notUploaded = "Not Uploaded"
    case uploading = "Uploading"
    case failed = "Failed"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .uploaded: return "checkmark.icloud.fill"
        case .notUploaded: return "iphone"
        case .uploading: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .uploaded: return .green
        case .notUploaded: return .gray
        case .uploading: return .brandNavy
        case .failed: return .red
        }
    }
}
