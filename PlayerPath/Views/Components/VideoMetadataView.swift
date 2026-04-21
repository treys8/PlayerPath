//
//  VideoMetadataView.swift
//  PlayerPath
//

import SwiftUI

struct VideoMetadata: Sendable {
    let duration: TimeInterval
    let fileSize: Int64
    let resolution: String?

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let mb = Double(fileSize) / 1_048_576
        if mb < 1 {
            let kb = Double(fileSize) / 1024
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.1f MB", mb)
    }

    var accessibilityDescription: String {
        var parts = [formattedDuration, formattedFileSize]
        if let resolution { parts.append(resolution) }
        return parts.joined(separator: ", ")
    }
}

struct VideoMetadataView: View {
    let metadata: VideoMetadata

    var body: some View {
        HStack(spacing: 12) {
            MetadataBadge(icon: "clock.fill", text: metadata.formattedDuration, color: .brandNavy)
            MetadataBadge(icon: "doc.fill", text: metadata.formattedFileSize, color: .green)
            if let resolution = metadata.resolution {
                MetadataBadge(icon: "video", text: resolution, color: .purple)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video info: \(metadata.accessibilityDescription)")
    }
}

struct MetadataBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.8))
        )
        .shadow(radius: 2)
    }
}
