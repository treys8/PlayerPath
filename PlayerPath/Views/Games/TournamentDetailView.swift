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
    @State private var showingDeleteConfirm = false

    private var rounds: [Game] { tournament.sortedRounds }

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
                }

                Button {
                    showingAddRound = true
                } label: {
                    Label("Add Round", systemImage: "plus.circle.fill")
                }
                .labelStyle(ActionRowLabelStyle())
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
            _ = await service.createGame(
                for: athlete, opponent: opponent, date: date, isLive: isLive,
                season: season, golfDetails: golf, location: location, tournament: tournament
            )
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
