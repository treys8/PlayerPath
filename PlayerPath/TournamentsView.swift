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
    
    // Tournament creation states
    @State private var newTournamentName = ""
    @State private var newTournamentLocation = ""
    @State private var newTournamentDate = Date()
    @State private var showingTournamentAlert = false
    
    var tournaments: [Tournament] {
        athlete?.tournaments.sorted { $0.date > $1.date } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if tournaments.isEmpty {
                    EmptyTournamentsView {
                        showingTournamentAlert = true
                    }
                } else {
                    List {
                        ForEach(tournaments) { tournament in
                            NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                                TournamentRow(tournament: tournament)
                            }
                        }
                        .onDelete(perform: deleteTournaments)
                    }
                }
            }
            .navigationTitle("Tournaments")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingTournamentAlert = true }) {
                        Image(systemName: "plus")
                    }
                }
                
                if !tournaments.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .alert("New Tournament", isPresented: $showingTournamentAlert, actions: {
            TextField("Tournament Name", text: $newTournamentName)
            TextField("Location", text: $newTournamentLocation)
            Button("Cancel", role: .cancel) {
                resetTournamentFields()
            }
            Button("Create") {
                createTournament()
            }
            .disabled(newTournamentName.isEmpty || newTournamentLocation.isEmpty)
        }, message: {
            Text("Enter tournament name and location")
        })
    }
    
    private func resetTournamentFields() {
        newTournamentName = ""
        newTournamentLocation = ""
        newTournamentDate = Date()
    }
    
    private func createTournament() {
        guard let athlete = athlete else { return }
        
        let tournament = Tournament(
            name: newTournamentName,
            date: newTournamentDate,
            location: newTournamentLocation
        )
        tournament.athlete = athlete
        tournament.isActive = true  // Automatically make new tournaments active
        
        athlete.tournaments.append(tournament)
        modelContext.insert(tournament)
        
        do {
            try modelContext.save()
            resetTournamentFields()
        } catch {
            print("Failed to save tournament: \(error)")
        }
    }
    
    private func deleteTournaments(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let tournament = tournaments[index]
                modelContext.delete(tournament)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete tournaments: \(error)")
            }
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
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
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
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        
                        Text("ACTIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Text("INACTIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Text(tournament.location)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text(tournament.date, formatter: DateFormatter.shortDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(tournament.games.count) games")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
        .background(tournament.isActive ? Color.green.opacity(0.02) : Color.clear)
        .cornerRadius(8)
    }
}

struct TournamentDetailView: View {
    let tournament: Tournament
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGame = false
    @State private var showingEndTournament = false
    
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
                        Text(tournament.date, formatter: DateFormatter.shortDate)
                            .foregroundColor(.secondary)
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
                if tournament.games.isEmpty {
                    HStack {
                        Text("No games yet")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Add Game") {
                            showingAddGame = true
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(tournament.games.sorted { $0.date > $1.date }) { game in
                        NavigationLink(destination: GameDetailView(game: game)) {
                            GameRow(game: game)
                        }
                    }
                }
            }
            
            // Actions Section
            Section("Tournament Actions") {
                if tournament.isActive {
                    Button(action: { showingEndTournament = true }) {
                        Label("End Tournament", systemImage: "stop.circle.fill")
                            .foregroundColor(.red)
                    }
                    
                    Text("This tournament is currently active")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button("Reactivate Tournament") {
                        tournament.isActive = true
                        try? modelContext.save()
                    }
                    .foregroundColor(.green)
                    
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
            }
        }
        .sheet(isPresented: $showingAddGame) {
            AddGameView(athlete: tournament.athlete, tournament: tournament)
        }
        .alert("End Tournament", isPresented: $showingEndTournament) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                tournament.isActive = false
                // End all live games in this tournament
                tournament.games.forEach { $0.isLive = false }
                try? modelContext.save()
            }
        } message: {
            Text("Are you sure you want to end this tournament? All live games will be stopped.")
        }
    }
}

struct AddTournamentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    
    @State private var name = ""
    @State private var location = ""
    @State private var info = ""
    @State private var date = Date()
    @State private var startActive = false
    
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
                    .disabled(name.isEmpty || location.isEmpty)
                }
            }
        }
    }
    
    private func saveTournament() {
        guard let athlete = athlete else { return }
        
        let tournament = Tournament(
            name: name,
            date: date,
            location: location,
            info: info
        )
        tournament.isActive = startActive
        tournament.athlete = athlete
        
        athlete.tournaments.append(tournament)
        modelContext.insert(tournament)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save tournament: \(error)")
        }
    }
}

// MARK: - Game Row Component
struct GameRow: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if game.isLive {
                    Text("LIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                } else if game.isComplete {
                    Text("FINAL")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            
            HStack {
                Text(game.date, formatter: DateFormatter.shortDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(game.videoClips.count) clips")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TournamentsView(athlete: nil)
}