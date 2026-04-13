//
//  UpcomingSessionCard.swift
//  PlayerPath
//
//  Dashboard card for scheduled coach sessions. Shows athlete names,
//  scheduled date/time, and a Start button to go live.
//

import SwiftUI

struct UpcomingSessionCard: View {
    let session: CoachSession
    var isStarting: Bool = false
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEditNotes: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            // Calendar icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
            }

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.athleteNamesSummary)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let date = session.scheduledDate {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if let notes = session.notes, !notes.isEmpty {
                    Button {
                        onEditNotes?()
                    } label: {
                        HStack(spacing: 4) {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else if onEditNotes != nil {
                    Button {
                        onEditNotes?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.caption2)
                            Text("Add notes")
                                .font(.caption)
                        }
                        .foregroundColor(.blue.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if let onStart {
                Button {
                    Haptics.medium()
                    onStart()
                } label: {
                    Group {
                        if isStarting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Go Live")
                        }
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [.red, .red.opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .disabled(isStarting)
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .contextMenu {
            if let onStart {
                Button {
                    onStart()
                } label: {
                    Label("Go Live", systemImage: "record.circle")
                }
            }
            if let onEditNotes {
                Button {
                    onEditNotes()
                } label: {
                    Label("Edit Notes", systemImage: "note.text")
                }
            }
            if let onCancel {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Label("Cancel Session", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduled session with \(session.athleteNamesSummary)")
    }
}
