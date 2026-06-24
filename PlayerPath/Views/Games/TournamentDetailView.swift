//
//  TournamentDetailView.swift
//  PlayerPath
//
//  Detail screen for a multi-round golf tournament (SchemaV27). Shows the
//  aggregate stroke-play total + to-par, lists the rounds (each links to the
//  existing GameDetailView), and lets the athlete add a round or delete the
//  tournament. Deleting a tournament UNLINKS its rounds — they survive as
//  standalone rounds (see GolfTournament.delete(in:)).
//

import SwiftUI
import SwiftData

struct TournamentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tournament: GolfTournament

    @State private var showingAddRound = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    /// Set when createGame fails (e.g. .noActiveSeason / .saveFailed) so the
    /// failure surfaces instead of being silently swallowed by addRound.
    @State private var addRoundError: String?

    private var rounds: [Game] { tournament.sortedRounds }
    /// At least one round carries per-hole scores → show the full holes matrix;
    /// otherwise the grid falls back to a compact totals-only table.
    private var anyRoundHasHoleScores: Bool {
        rounds.contains { !($0.holeScores ?? []).isEmpty }
    }
    /// Any round has a usable total (per-hole or quick-entry) → worth showing a grid.
    private var anyRoundScored: Bool {
        rounds.contains { $0.effectiveTotalScore != nil }
    }

    var body: some View {
        List {
            scoreSection

            Section(header: Text("Rounds").smallCapsLabel()) {
                if rounds.isEmpty {
                    Text("No rounds yet. Add your first round below.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rounds) { round in
                        NavigationLink(destination: GameDetailView(game: round)) {
                            roundRow(round)
                        }
                    }
                    .onMove(perform: reorderRounds)
                }

                Button {
                    showingAddRound = true
                } label: {
                    Label("Add Round", systemImage: "plus.circle.fill")
                }
                .labelStyle(ActionRowLabelStyle())
            }

            // Round-by-round comparison. Full holes matrix when any round has
            // per-hole scores; otherwise a compact totals-only table so quick-entry
            // tournaments still get a side-by-side leaderboard.
            if anyRoundScored {
                Section(header: Text("Scorecard").smallCapsLabel()) {
                    TournamentScorecardGrid(rounds: rounds, includeHoleDetails: anyRoundHasHoleScores)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            if let notes = tournament.notes, !notes.isEmpty {
                Section(header: Text("Notes").smallCapsLabel()) {
                    Text(notes).font(.bodySmall)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Tournament", systemImage: "trash")
                }
                .labelStyle(DestructiveRowLabelStyle())
            }
        }
        .ppDetailBackground()
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Reorder handles (drag-to-renumber) appear only with 2+ rounds.
            if rounds.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit Tournament", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditTournamentSheet(tournament: tournament)
        }
        .sheet(isPresented: $showingAddRound) {
            GameCreationView(
                athlete: tournament.athlete,
                preselectedTournament: tournament,
                onSave: { opponent, date, isLive, season, golf, location, pickedTournament in
                    addRound(opponent: opponent, date: date, isLive: isLive,
                             season: season, golf: golf, location: location,
                             tournament: pickedTournament ?? tournament)
                }
            )
        }
        .alert("Delete Tournament", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteTournament() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the tournament. Its rounds are kept as standalone rounds.")
        }
        .alert("Couldn't Add Round", isPresented: .init(
            get: { addRoundError != nil },
            set: { if !$0 { addRoundError = nil } }
        )) {
            Button("OK", role: .cancel) { addRoundError = nil }
        } message: {
            Text(addRoundError ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var scoreSection: some View {
        Section {
            HStack {
                Text("Total")
                Spacer()
                if let total = tournament.totalStrokes {
                    Text("\(total)")
                        .font(.title3).bold()
                    if let toPar = tournament.displayToPar {
                        Text("(\(toPar))")
                            .foregroundStyle(toParColor)
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if let dateText {
                LabeledContent("Date", value: dateText)
            }
            if let loc = tournament.location, !loc.isEmpty {
                LabeledContent("Location", value: loc)
            }
            LabeledContent("Scored Rounds", value: "\(tournament.scoredRounds.count) of \(rounds.count)")
        }
    }

    private func roundRow(_ round: Game) -> some View {
        HStack {
            Text("Round \(round.roundNumber.map(String.init) ?? "—")")
                .font(.bodyMedium)
            if round.isLive {
                Text("LIVE")
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
            Spacer()
            if let score = round.effectiveTotalScore {
                Text("\(score)")
                    .font(.bodyMedium)
                if let par = round.effectivePar {
                    let delta = score - par
                    Text(delta == 0 ? "E" : (delta > 0 ? "+\(delta)" : "\(delta)"))
                        .font(.bodySmall)
                        .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .red : .secondary))
                }
            } else {
                Text("Not scored")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Derived

    private var dateText: String? {
        guard let start = tournament.startDate else { return nil }
        if let end = tournament.endDate, !Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(DateFormatter.monthDay.string(from: start)) – \(DateFormatter.monthDay.string(from: end))"
        }
        return DateFormatter.mediumDate.string(from: start)
    }

    private var toParColor: Color {
        guard let toPar = tournament.totalToPar else { return .secondary }
        if toPar < 0 { return .green }
        if toPar > 0 { return .red }
        return .secondary
    }

    // MARK: - Actions

    private func addRound(opponent: String, date: Date, isLive: Bool, season: Season?,
                          golf: GolfRoundDetails?, location: String?, tournament: GolfTournament) {
        guard let athlete = tournament.athlete else { return }
        let service = GameService(modelContext: modelContext)
        Task {
            let result = await service.createGame(
                for: athlete, opponent: opponent, date: date, isLive: isLive,
                season: season, golfDetails: golf, location: location, tournament: tournament
            )
            // Surface failures (e.g. .noActiveSeason / .saveFailed) instead of
            // silently swallowing them. The view is MainActor-isolated, so
            // setting @State here is safe.
            if case .failure(let error) = result {
                addRoundError = error.localizedDescription
            }
        }
    }

    /// Drag-to-renumber. Resequences `roundNumber` 1…N over the new order (also
    /// healing any legacy nil numbers), dirties each moved round + the tournament,
    /// then pushes the change. Last-write-wins across devices — acceptable for a
    /// rarely-concurrent action.
    private func reorderRounds(from source: IndexSet, to destination: Int) {
        var ordered = rounds
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, round) in ordered.enumerated() {
            let newNumber = index + 1
            if round.roundNumber != newNumber {
                round.roundNumber = newNumber
                round.needsSync = true
            }
        }
        tournament.needsSync = true
        // On save failure roll back the renumber so the grid and the dirty flags
        // don't drift from disk, and skip the sync kick (mirrors EditGameSheet).
        guard ErrorHandlerService.shared.saveContext(modelContext, caller: "TournamentDetailView.reorderRounds") else {
            modelContext.rollback()
            return
        }
        if let user = tournament.athlete?.user {
            Task { try? await SyncCoordinator.shared.syncGames(for: user) }
        }
    }

    private func deleteTournament() {
        let user = tournament.athlete?.user
        let firestoreId = tournament.firestoreId
        if let firestoreId, let user {
            let userId = user.firebaseAuthUid ?? user.id.uuidString
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deleteGolfTournament(userId: userId, tournamentId: firestoreId)
                }
            }
        }
        tournament.delete(in: modelContext)
        ErrorHandlerService.shared.saveContext(modelContext, caller: "TournamentDetailView.deleteTournament")
        if let user {
            Task {
                try? await SyncCoordinator.shared.syncGolfTournaments(for: user)
                try? await SyncCoordinator.shared.syncGames(for: user)
            }
        }
        dismiss()
    }
}
