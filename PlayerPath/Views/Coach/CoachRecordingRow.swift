//
//  CoachRecordingRow.swift
//  PlayerPath
//
//  Row view for a private recording in the coach Recordings tab.
//

import SwiftUI

struct CoachRecordingRow: View {
    let item: CoachRecordingItem
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let urlString = item.video.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: 72, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.athleteName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(item.folderName)
                    .font(.caption)
                    .foregroundColor(.green)

                HStack(spacing: 6) {
                    if let createdAt = item.video.createdAt {
                        Text(createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let duration = item.video.duration, duration > 0 {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if let fileSize = item.video.fileSize, fileSize > 0 {
                Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                onMove()
            } label: {
                Label("Share with Athlete", systemImage: "arrow.right.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onMove()
            } label: {
                Label("Share", systemImage: "arrow.right.circle")
            }
            .tint(.green)
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "video.fill")
                .foregroundColor(.gray)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
