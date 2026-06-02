//
//  EventTargetPicker.swift
//  PlayerPath
//
//  Shared event picker for tagging one OR many photos to a game/round or
//  practice. Golf athletes see rounds grouped under their tournaments
//  ("Round N · course"), with standalone rounds listed separately — so the
//  picker is honest about the round/tournament hierarchy instead of listing
//  every round flat under a "Tournaments" header.
//
//  Used by both the single-photo PhotoTagSheet (showsSelection = true, with
//  checkmarks) and the multi-select BatchPhotoTagSheet (callback only).
//

import SwiftUI
import SwiftData

struct EventTargetPicker: View {
    enum Target {
        case game(Game)
        case practice(Practice)
        case clear
    }

    let athlete: Athlete
    var selectedGameID: UUID? = nil
    var selectedPracticeID: UUID? = nil
    /// When true, a checkmark marks the current selection (single-photo mode).
    var showsSelection: Bool = false
    let onSelect: (Target) -> Void

    @Environment(\.ppAccent) private var ppAccent

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }

    private var games: [Game] {
        (athlete.games ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    /// Golf rounds that don't belong to a tournament (or all games, non-golf).
    private var standaloneGames: [Game] {
        games.filter { $0.tournament == nil }
    }
    private var tournaments: [GolfTournament] {
        (athlete.golfTournaments ?? []).sorted {
            ($0.startDate ?? $0.createdAt ?? .distantPast) > ($1.startDate ?? $1.createdAt ?? .distantPast)
        }
    }
    private var practices: [Practice] {
        (athlete.practices ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var hasAnyEvent: Bool {
        !games.isEmpty || !practices.isEmpty
    }

    var body: some View {
        List {
            // Clear / no-event row. In single-photo mode it's checked when the
            // photo isn't tagged; in batch mode it un-tags the whole selection.
            Section {
                eventRow(
                    title: "No event",
                    date: nil,
                    isSelected: showsSelection && selectedGameID == nil && selectedPracticeID == nil
                ) { onSelect(.clear) }
            }

            if isGolf {
                // One section per tournament, listing its rounds in order.
                ForEach(tournaments) { tournament in
                    let rounds = tournament.sortedRounds
                    if !rounds.isEmpty {
                        Section(header: Text(tournament.name).smallCapsLabel()) {
                            ForEach(rounds) { round in
                                eventRow(
                                    title: roundTitle(round),
                                    date: round.date,
                                    isSelected: showsSelection && selectedGameID == round.id
                                ) { onSelect(.game(round)) }
                            }
                        }
                    }
                }
                // Rounds that aren't part of any tournament.
                if !standaloneGames.isEmpty {
                    Section(header: Text(tournaments.isEmpty ? "Rounds" : "Individual Rounds").smallCapsLabel()) {
                        ForEach(standaloneGames) { round in
                            eventRow(
                                title: "at \(round.opponent)",
                                date: round.date,
                                isSelected: showsSelection && selectedGameID == round.id
                            ) { onSelect(.game(round)) }
                        }
                    }
                }
            } else if !games.isEmpty {
                Section(header: Text("Games").smallCapsLabel()) {
                    ForEach(games) { game in
                        eventRow(
                            title: "vs \(game.opponent)",
                            date: game.date,
                            isSelected: showsSelection && selectedGameID == game.id
                        ) { onSelect(.game(game)) }
                    }
                }
            }

            if !practices.isEmpty {
                Section(header: Text("Practices").smallCapsLabel()) {
                    ForEach(practices) { practice in
                        eventRow(
                            title: "Practice",
                            date: practice.date,
                            isSelected: showsSelection && selectedPracticeID == practice.id
                        ) { onSelect(.practice(practice)) }
                    }
                }
            }

            if !hasAnyEvent {
                Section {
                    Text("Create a game or practice first to tag photos to it.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// "Round 2 · Pebble Beach" — falls back to the course alone when a round
    /// has no number (legacy / not-yet-numbered tournament rounds).
    private func roundTitle(_ round: Game) -> String {
        if let n = round.roundNumber { return "Round \(n) · \(round.opponent)" }
        return round.opponent
    }

    @ViewBuilder
    private func eventRow(title: String, date: Date?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    if let date {
                        Text(date, style: .date)
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(ppAccent)
                }
            }
        }
    }
}
