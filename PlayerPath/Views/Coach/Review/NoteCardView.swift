//
//  NoteCardView.swift
//  PlayerPath
//
//  Single-note row inside NotesTabView — handles tap-to-seek, context
//  menu (delete/report), and drawing indicator.
//

import SwiftUI

struct NoteCardView: View {
    let note: VideoAnnotation
    let canDelete: Bool
    let onDelete: () -> Void
    let onSeek: () -> Void

    @State private var showingDeleteAlert = false
    @State private var showingReportAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: note.isCoachComment ? "person.fill.checkmark" : "person.fill")
                    .font(.caption)
                    .foregroundColor(note.isCoachComment ? .brandNavy : .secondary)

                Text(note.userName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(note.isCoachComment ? .brandNavy : .secondary)

                if note.isCoachComment {
                    Text("COACH")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandNavy.opacity(0.2))
                        .foregroundColor(.brandNavy)
                        .cornerRadius(4)
                }

                Spacer()
            }

            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text(note.timestamp.formattedTimestamp)
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundColor(.secondary)

            if note.isDrawing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip")
                        .font(.subheadline)
                        .foregroundColor(.brandNavy)
                    Text("Tap to view drawing")
                        .font(.subheadline)
                        .foregroundColor(.brandNavy)
                }
            } else {
                Text(note.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let createdAt = note.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek()
        }
        .overlay(alignment: .leading) {
            if let cat = note.annotationCategory {
                RoundedRectangle(cornerRadius: 2)
                    .fill(cat.color)
                    .frame(width: 4)
                    .padding(.vertical, 8)
            }
        }
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    Haptics.warning()
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    showingReportAlert = true
                } label: {
                    Label("Report Comment", systemImage: "flag")
                }
            }
        }
        .alert("Delete Note", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this note?")
        }
        .alert("Report Comment", isPresented: $showingReportAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Report", role: .destructive) {
                let subject = "Inappropriate Comment Report"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let body = "I would like to report the following comment as inappropriate:\n\nComment by: \(note.userName)\nComment: \(note.text)\n\nDetails:\n[Please describe the issue here]"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let mailto = "mailto:\(AuthConstants.supportEmail)?subject=\(subject)&body=\(body)"
                if let url = URL(string: mailto) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Report this comment to PlayerPath support for review?")
        }
    }
}
