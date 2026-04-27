//
//  PitchSpeedsView.swift
//  PlayerPath
//
//  Lists every recorded pitch speed for an athlete, filtered by pitch type
//  ("fastball" or "offspeed"), newest first.
//

import SwiftUI

struct PitchSpeedsView: View {
    let athlete: Athlete
    /// "fastball" or "offspeed"
    let pitchType: String

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        pitchType == "fastball" ? "Fastball Speeds" : "Off-Speed Speeds"
    }

    private var emptyTitle: String {
        pitchType == "fastball" ? "No Fastball Speeds" : "No Off-Speed Speeds"
    }

    private var emptyDescription: String {
        let kind = pitchType == "fastball" ? "Fastball" : "Off-speed"
        return "\(kind) speeds you enter when recording pitches will appear here."
    }

    private var accentColor: Color {
        pitchType == "fastball" ? .green : .orange
    }

    private struct PitchEntry: Identifiable {
        let id: UUID
        let speed: Double
        let date: Date
        let context: String
    }

    private var entries: [PitchEntry] {
        let clips = athlete.videoClips ?? []
        return clips.compactMap { clip -> PitchEntry? in
            guard clip.pitchType == pitchType,
                  let speed = clip.pitchSpeed,
                  speed > 0 else { return nil }
            let context: String
            if let opponent = clip.gameOpponent ?? clip.game?.opponent {
                context = "vs \(opponent)"
            } else if clip.practice != nil || clip.practiceDate != nil {
                context = "Practice"
            } else {
                context = "Clip"
            }
            return PitchEntry(
                id: clip.id,
                speed: speed,
                date: clip.createdAt ?? Date.distantPast,
                context: context
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var averageSpeed: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.speed).reduce(0, +) / Double(entries.count)
    }

    private var topSpeed: Double {
        entries.map(\.speed).max() ?? 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "speedometer",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        Section {
                            HStack(spacing: 16) {
                                summaryCell(title: "Average", value: String(format: "%.1f", averageSpeed), unit: "MPH")
                                Divider().frame(height: 40)
                                summaryCell(title: "Top", value: String(format: "%.1f", topSpeed), unit: "MPH")
                                Divider().frame(height: 40)
                                summaryCell(title: "Pitches", value: "\(entries.count)", unit: nil)
                            }
                            .padding(.vertical, 6)
                        }

                        Section(pitchType == "fastball" ? "All Fastballs" : "All Off-Speed") {
                            ForEach(entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(format: "%.1f MPH", entry.speed))
                                            .font(.ppStatSmall)
                                            .monospacedDigit()
                                        Text(entry.context)
                                            .font(.bodySmall)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                                        .font(.bodySmall)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func summaryCell(title: String, value: String, unit: String?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ppStatMedium)
                .monospacedDigit()
                .foregroundStyle(accentColor)
            if let unit {
                Text(unit)
                    .font(.labelSmall)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.bodySmall)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
