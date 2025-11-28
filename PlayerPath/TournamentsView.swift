//
//  TournamentsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct TournamentsView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tournament.date, order: .reverse) private var allTournaments: [Tournament]

    @State private var showingAddTournament = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var errorMessage: String?
    @State private var showingError = false

    private var tournaments: [Tournament] {
        guard let athleteId = athlete?.id else { return [] }
        return allTournaments.filter { tournament in
            tournament.athletes?.contains(where: { $0.id == athleteId }) ?? false
        }
    }

    var body: some View {
        Group {
            if tournaments.isEmpty {
                EmptyTournamentsView {
                    showingAddTournament = true
                }
            } else {
                List {
                    ForEach(tournaments) { tournament in
                        NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                            TournamentRow(tournament: tournament)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let index = tournaments.firstIndex(where: { $0.id == tournament.id }) {
                                    pendingDeleteOffsets = IndexSet([index])
                                    showDeleteConfirm = true
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        pendingDeleteOffsets = offsets
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle("Tournaments")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTournament = true }) {
                    Image(systemName: "plus")
                }
            }

            if !tournaments.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAddTournament) {
            if let athlete = athlete {
                AddTournamentView(athlete: athlete)
            }
        }
        .alert("Delete Tournaments", isPresented: $showDeleteConfirm, presenting: pendingDeleteOffsets) { offsets in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    deleteTournaments(offsets: offsets)
                }
            }
        } message: { _ in
            Text("Are you sure you want to delete the selected tournaments?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func deleteTournaments(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tournaments[index])
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct EmptyTournamentsView: View {
    let onAddTournament: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "trophy")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            Text("No Tournaments Yet")
                .font(.title)
                .fontWeight(.bold)

            Text("Create your first tournament to track games and performance")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onAddTournament) {
                Text("Add Tournament")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
    }
}

struct PPStatusChip: View {
    enum Style { case active, inactive, live, final }
    let style: Style
    var body: some View {
        let config: (text: String, fg: Color, bg: Color) = {
            switch style {
            case .active: return ("ACTIVE", .green, Color.green.opacity(0.1))
            case .inactive: return ("INACTIVE", .gray, Color.gray.opacity(0.1))
            case .live: return ("LIVE", .white, .red)
            case .final: return ("FINAL", .white, .gray)
            }
        }()
        return Text(config.text)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(config.fg)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(config.bg)
            )
    }
}

struct TournamentRow: View {
    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tournament.name)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if tournament.isActive {
                    PPStatusChip(style: .active)
                }
            }

            Text(tournament.location)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                if let date = tournament.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(tournament.games?.count ?? 0) games")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TournamentDetailView: View {
    let tournament: Tournament
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGame = false
    @State private var showingEndTournament = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var sortedGames: [Game] = []

    private var athlete: Athlete? {
        tournament.athletes?.first
    }

    var body: some View {
        List {
            Section("Tournament Info") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Location")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(tournament.location)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = tournament.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !tournament.info.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Info")
                                .fontWeight(.semibold)
                            Text(tournament.info)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            Section("Games") {
                if sortedGames.isEmpty {
                    Button("Add Game") {
                        showingAddGame = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    ForEach(sortedGames) { game in
                        NavigationLink(destination: GameDetailView(game: game)) {
                            TournamentGameRow(game: game)
                        }
                    }
                }
            }

            Section("Tournament Actions") {
                if tournament.isActive {
                    Button(action: { showingEndTournament = true }) {
                        Label("End Tournament", systemImage: "stop.circle.fill")
                    }
                    .tint(.red)
                } else {
                    Button("Reactivate Tournament") {
                        tournament.isActive = true
                        try? modelContext.save()
                    }
                    .tint(.green)
                }
            }
        }
        .navigationTitle(tournament.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Game") {
                    showingAddGame = true
                }
            }
        }
        .onAppear {
            updateGames()
        }
        .onChange(of: tournament.games) { _, _ in
            updateGames()
        }
        .sheet(isPresented: $showingAddGame) {
            if let athlete = athlete {
                AddGameView(athlete: athlete, tournament: tournament)
            }
        }
        .alert("End Tournament", isPresented: $showingEndTournament) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endTournament()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func endTournament() {
        // Save previous game states for rollback
        let previousGameStates = (tournament.games ?? []).map { ($0, $0.isLive) }

        // Make changes
        tournament.isActive = false
        (tournament.games ?? []).forEach { $0.isLive = false }

        // Try to save
        do {
            try modelContext.save()
        } catch {
            // Revert ALL changes on failure
            tournament.isActive = true
            for (game, wasLive) in previousGameStates {
                game.isLive = wasLive
            }
            errorMessage = "Failed to end tournament: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func updateGames() {
        sortedGames = (tournament.games ?? []).sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }
}

struct AddTournamentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete

    @State private var name = ""
    @State private var location = ""
    @State private var info = ""
    @State private var date = Date()
    @State private var startActive = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tournament Details") {
                    TextField("Tournament Name", text: $name)
                    TextField("Location", text: $location)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Additional Info") {
                    TextField("Info/Notes", text: $info, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Start as Active", isOn: $startActive)
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTournament()
                    }
                    .disabled(name.isEmpty || location.isEmpty || isSaving)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func saveTournament() {
        guard !name.isEmpty, !location.isEmpty else { return }

        isSaving = true

        let tournament = Tournament(
            name: name.trimmingCharacters(in: .whitespaces),
            date: date,
            location: location.trimmingCharacters(in: .whitespaces),
            info: info.trimmingCharacters(in: .whitespaces)
        )
        tournament.isActive = startActive

        // Set BOTH sides of the relationship
        tournament.athletes = [athlete]

        if athlete.tournaments == nil {
            athlete.tournaments = []
        }
        athlete.tournaments?.append(tournament)

        if let season = athlete.activeSeason {
            tournament.season = season
        }

        modelContext.insert(tournament)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "Failed to save: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct TournamentGameRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if game.isLive {
                    PPStatusChip(style: .live)
                } else if game.isComplete {
                    PPStatusChip(style: .final)
                }
            }

            HStack {
                if let date = game.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(game.videoClips?.count ?? 0) clips")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text(message)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}

#Preview {
    TournamentsView(athlete: Athlete(name: "Preview"))
}
