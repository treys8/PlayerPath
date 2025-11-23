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
    
    // Tournament creation state
    @State private var showingAddTournament = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // Cached sorted tournaments to avoid repeated sorting on every body evaluation
    @State private var tournaments: [Tournament] = []
    
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddTournament = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add tournament")
                .controlSize(.regular)
            }
            
            if !tournaments.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                        .accessibilityLabel("Edit tournaments")
                }
            }
        }
        .onAppear {
            updateTournaments()
        }
        .onChange(of: athlete?.tournaments) { _, _ in
            updateTournaments()
        }
        .sheet(isPresented: $showingAddTournament) {
            AddTournamentView(athlete: athlete) {
                updateTournaments()
            }
        }
        .alert("Delete Tournaments", isPresented: $showDeleteConfirm, presenting: pendingDeleteOffsets) { offsets in
            Button("Cancel", role: .cancel) { pendingDeleteOffsets = nil }
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets { deleteTournaments(offsets: offsets) }
                pendingDeleteOffsets = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete the selected tournaments? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                showingError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func updateTournaments() {
        tournaments = (athlete?.tournaments ?? []).sorted { 
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast) 
        }
    }
    
    private func deleteTournaments(offsets: IndexSet) {
        let tournamentsToDelete = offsets.map { tournaments[$0] }
        
        do {
            for tournament in tournamentsToDelete {
                modelContext.delete(tournament)
            }
            try modelContext.save()
            updateTournaments()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to delete tournaments: \(error.localizedDescription)"
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
            
            Text("Create your first tournament to start tracking games and performances")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onAddTournament) {
                Text("Add Tournament")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
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
            .accessibilityLabel(config.text.capitalized)
    }
}

struct TournamentRow: View {
    let tournament: Tournament
    
    private var gameCount: Int {
        tournament.games?.count ?? 0
    }
    
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
                } else {
                    Text("Date TBA")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(gameCount) \(gameCount == 1 ? "game" : "games")")
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
    
    // Get the athlete from the tournament's athletes relationship
    private var athlete: Athlete? {
        tournament.athletes?.first
    }
    
    private var gameCount: Int {
        tournament.games?.count ?? 0
    }
    
    var body: some View {
        List {
            // Tournament Info Section
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
                        } else {
                            Text("Date TBA")
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
            
            // Games Section
            Section("Games") {
                if gameCount == 0 {
                    HStack {
                        Text("No games yet")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Add Game") {
                            showingAddGame = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                } else {
                    ForEach(sortedGames) { game in
                        NavigationLink(destination: GameDetailView(game: game)) {
                            TournamentGameRow(game: game)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !game.isComplete {
                                if !game.isLive {
                                    Button {
                                        setGameLive(game)
                                    } label: {
                                        Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
                                    }
                                    .tint(.red)
                                }
                                Button(role: .destructive) {
                                    endGame(game)
                                } label: {
                                    Label("End", systemImage: "stop.circle")
                                }
                            }
                        }
                    }
                }
            }
            
            // Actions Section
            Section("Tournament Actions") {
                if tournament.isActive {
                    Button(action: { showingEndTournament = true }) {
                        Label("End Tournament", systemImage: "stop.circle.fill")
                    }
                    .tint(.red)
                    
                    Text("This tournament is currently active")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button("Reactivate Tournament") {
                        reactivateTournament()
                    }
                    .tint(.green)
                    
                    Text("This tournament is inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add Game") {
                    showingAddGame = true
                }
                .accessibilityLabel("Add game")
                .controlSize(.regular)
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
            } else {
                ErrorMessageView(message: "Cannot add game: No athlete associated with this tournament")
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if !Task.isCancelled {
                            showingAddGame = false
                        }
                    }
            }
        }
        .alert("End Tournament", isPresented: $showingEndTournament) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endTournament()
            }
        } message: {
            Text("Are you sure you want to end this tournament? All live games will be stopped.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                showingError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateGames() {
        sortedGames = (tournament.games ?? []).sorted { 
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast) 
        }
    }
    
    private func setGameLive(_ game: Game) {
        do {
            game.isLive = true
            try modelContext.save()
            updateGames()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to start game: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func endGame(_ game: Game) {
        do {
            game.isLive = false
            game.isComplete = true
            try modelContext.save()
            updateGames()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to end game: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func reactivateTournament() {
        do {
            tournament.isActive = true
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to reactivate tournament: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func endTournament() {
        do {
            tournament.isActive = false
            // End all live games in this tournament
            tournament.games?.forEach { $0.isLive = false }
            try modelContext.save()
            updateGames()
        } catch {
            modelContext.rollback()
            errorMessage = "Failed to end tournament: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct AddTournamentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    let onTournamentCreated: () -> Void
    
    @State private var name = ""
    @State private var location = ""
    @State private var info = ""
    @State private var date = Date()
    @State private var startActive = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isSaving = false
    
    init(athlete: Athlete?, onTournamentCreated: @escaping () -> Void = {}) {
        self.athlete = athlete
        self.onTournamentCreated = onTournamentCreated
    }
    
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTournament()
                    }
                    .disabled(name.isEmpty || location.isEmpty || isSaving)
                }
            }
        }
        .disabled(isSaving)
        .overlay {
            if isSaving {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                showingError = false
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func saveTournament() {
        guard let athlete = athlete else {
            errorMessage = "No athlete selected. Cannot create tournament."
            showingError = true
            return
        }
        
        isSaving = true
        
        do {
            let tournament = Tournament(
                name: name,
                date: date,
                location: location,
                info: info
            )
            tournament.isActive = startActive
            
            // SwiftData handles bidirectional relationships automatically
            // Just set one side of the relationship
            tournament.athletes = [athlete]
            
            modelContext.insert(tournament)
            try modelContext.save()
            
            onTournamentCreated()
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            errorMessage = "Failed to save tournament: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Game Row Component
struct TournamentGameRow: View {
    let game: Game
    
    private var clipCount: Int {
        game.videoClips?.count ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if game.isLive {
                    PPStatusChip(style: PPStatusChip.Style.live)
                } else if game.isComplete {
                    PPStatusChip(style: PPStatusChip.Style.final)
                }
            }
            
            HStack {
                if let date = game.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Date TBA")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(clipCount) clips")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Error Message View
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
    TournamentsView(athlete: nil)
}
