//
//  JournalView.swift
//  PlayerPath
//
//  Visual overhaul — the Journal landing tab.
//  A calm, reverse-chronological feed of the athlete's games, practices, and
//  standalone clips. A compact "Live Now" strip pins to the top when an
//  activity is live (tap opens the existing detail screen, where End/Score/
//  Record already live — no duplicated state machine here). Filter pills scope
//  the feed: All / Games / Golf / Highlights.
//
//  This is a NEW screen; DashboardView is preserved and reachable elsewhere.
//

import SwiftUI
import SwiftData

struct JournalView: View {
    let user: User
    let athlete: Athlete
    @Binding var homePath: NavigationPath

    @Environment(\.modelContext) private var modelContext
    private var activeSport: Season.SportType { athlete.sportType }

    @State private var filter: JournalFilter = .all

    private let athleteID: UUID
    @Query private var games: [Game]
    @Query private var practices: [Practice]
    @Query private var clips: [VideoClip]

    init(user: User, athlete: Athlete, homePath: Binding<NavigationPath>) {
        self.user = user
        self.athlete = athlete
        self._homePath = homePath
        let id = athlete.id
        self.athleteID = id
        self._games = Query(
            filter: #Predicate<Game> { $0.athlete?.id == id },
            sort: [SortDescriptor(\Game.date, order: .reverse)]
        )
        self._practices = Query(
            filter: #Predicate<Practice> { $0.athlete?.id == id },
            sort: [SortDescriptor(\Practice.date, order: .reverse)]
        )
        self._clips = Query(
            filter: #Predicate<VideoClip> { $0.athlete?.id == id },
            sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
        )
    }

    // MARK: - Derived data

    /// Live games/practices for the active sport (display-only strip).
    private var liveGames: [Game] {
        games.filter { $0.isLive && sportMatches($0.season?.sport) }
    }

    private var livePractices: [Practice] {
        practices.filter { $0.isLive && sportMatches($0.season?.sport) }
    }

    private var hasLiveActivity: Bool {
        !liveGames.isEmpty || !livePractices.isEmpty
    }

    private func sportMatches(_ sport: Season.SportType?) -> Bool {
        guard let sport else { return true }   // seasonless passes through
        return sport == activeSport
    }

    private var entries: [JournalEntry] {
        JournalFeedBuilder.build(
            games: games,
            practices: practices,
            orphanClips: JournalFeedBuilder.orphans(from: clips),
            filter: filter
        )
    }

    /// Milestones across every season represented in the feed — feeds the
    /// per-row auto-headline and milestone marker. Pure compute (no Firestore).
    private var milestones: [Milestone] {
        var seenSeasonIDs = Set<UUID>()
        var result: [Milestone] = []
        for game in games {
            guard let season = game.season,
                  seenSeasonIDs.insert(season.id).inserted else { continue }
            result += MilestoneEngine.milestones(for: season)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: .spacingLarge) {
                if hasLiveActivity {
                    liveStrip
                }

                PPFilterPillRow(
                    options: JournalFilter.allCases,
                    title: { $0.title },
                    selection: $filter
                )

                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            destination(for: entry)
                        } label: {
                            JournalEntryRow(entry: entry, milestones: milestones)
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, .spacingLarge)
        }
        .background(Theme.surface)
        .navigationTitle("The Journal.")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                    Haptics.light()
                } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Live strip

    @ViewBuilder
    private var liveStrip: some View {
        VStack(spacing: .spacingMedium) {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                Text("Live Now").smallCapsLabel(color: Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 18)

            // Display-only cards: nil action closures, tap opens detail.
            ForEach(liveGames) { game in
                NavigationLink {
                    GameDetailView(game: game)
                } label: {
                    LiveGameCard(game: game)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
            }

            ForEach(livePractices) { practice in
                NavigationLink {
                    PracticeDetailView(practice: practice)
                } label: {
                    LiveGameCard(practiceRound: practice)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for entry: JournalEntry) -> some View {
        switch entry {
        case .game(let g):     GameDetailView(game: g)
        case .practice(let p): PracticeDetailView(practice: p)
        case .clip(let c):     VideoPlayerView(clip: c)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: .spacingMedium) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: .spacingXSmall) {
                Text("Start your journal")
                    .font(.ppTitle3)
                    .foregroundStyle(Theme.textPrimary)
                Text("Record your first clip or log a game.")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Haptics.medium()
                NotificationCenter.default.post(name: .switchTab, object: MainTab.games.rawValue)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                    Text("Log a Game")
                        .font(.ppHeadline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, .spacingSmall)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXLarge)
        .padding(.horizontal, .spacingLarge)
        .ppCard()
        .padding(.horizontal, 18)
        .padding(.top, 40)
    }
}
