//
//  DashboardLiveSection.swift
//  PlayerPath
//
//  Uses @Query to observe live games directly for reliable updates
//

import SwiftUI
import SwiftData

struct DashboardLiveSection: View {
    let athlete: Athlete

    // Query live games for this athlete only (same pattern as DashboardView)
    @Query private var liveGames: [Game]

    init(athlete: Athlete) {
        self.athlete = athlete
        let id = athlete.id
        self._liveGames = Query(
            filter: #Predicate<Game> { $0.isLive == true && $0.athlete?.id == id },
            sort: [SortDescriptor(\Game.date, order: .reverse)]
        )
    }

    var body: some View {
        liveGamesList
            .onReceive(NotificationCenter.default.publisher(for: .appWillEnterForeground)) { _ in
                staleGame = GameAlertService.shared.staleLiveGames(from: liveGames).first
            }
            .alert("Game Still Live", isPresented: Binding(
                get: { staleGame != nil },
                set: { if !$0 { staleGame = nil } }
            ), presenting: staleGame) { game in
                Button("End Game", role: .destructive) {
                    Task { await GameService(modelContext: modelContext).end(game) }
                    staleGame = nil
                }
                Button("Keep Going", role: .cancel) { staleGame = nil }
            } message: { game in
                let hours = Int(-(game.liveStartDate ?? Date()).timeIntervalSinceNow / 3600)
                Text("Your game vs \(game.opponent) has been live for \(hours)+ hours. Did you forget to end it?")
            }
    }

    @ViewBuilder
    private var liveGamesList: some View {
        if !liveGames.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Text("Live")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                // Display as vertical list for compactness
                VStack(spacing: 8) {
                    ForEach(liveGames, id: \.id) { game in
                        NavigationLink {
                            GameDetailView(game: game)
                        } label: {
                            HStack(spacing: 12) {
                                // Live indicator
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(game.opponent.isEmpty ? "Unknown" : game.opponent)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    if let date = game.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                // End button
                                Button {
                                    guard !endingGameIDs.contains(game.id) else { return }
                                    endingGameIDs.insert(game.id)
                                    Task {
                                        await GameService(modelContext: modelContext).end(game)
                                        endingGameIDs.remove(game.id)
                                    }
                                } label: {
                                    Text("End")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(endingGameIDs.contains(game.id) ? Color.gray : Color.red)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(endingGameIDs.contains(game.id))
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: liveGames.count)
        }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var endingGameIDs: Set<UUID> = []
    @State private var staleGame: Game? = nil
}
