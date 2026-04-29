//
//  CompletedSessionsListView.swift
//  PlayerPath
//
//  Sheet listing the coach's completed sessions with date, athletes, duration,
//  and clip count. Pushed from the Dashboard's lessons summary "View all" link.
//

import SwiftUI

struct CompletedSessionsListView: View {
    let sessions: [CoachSession]
    @Environment(\.dismiss) private var dismiss

    private var sortedSessions: [CoachSession] {
        sessions.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedSessions.isEmpty {
                    ContentUnavailableView(
                        "No completed sessions",
                        systemImage: "calendar",
                        description: Text("Sessions you complete will appear here with their duration and clip count.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedSessions, id: \.id) { session in
                        CompletedSessionRow(session: session)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Completed Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CompletedSessionRow: View {
    let session: CoachSession

    private var duration: TimeInterval {
        guard let start = session.startedAt, let end = session.endedAt else { return 0 }
        return max(0, end.timeIntervalSince(start))
    }

    private var dateLabel: String {
        guard let start = session.startedAt else { return "—" }
        return DateFormatter.mediumDate.string(from: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.athleteNamesSummary)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(dateLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(session.clipCount) clip\(session.clipCount == 1 ? "" : "s")",
                      systemImage: "video.fill")
                Label(duration.durationCompact, systemImage: "clock.fill")
                if let title = session.title, !title.isEmpty {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
