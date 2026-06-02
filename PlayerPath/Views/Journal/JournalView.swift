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

    /// True when this athlete has literally any game, practice, or clip on
    /// record — independent of the active filter. Drives the new-user welcome
    /// vs. the "this filter matched nothing" message: an athlete who HAS data
    /// but tapped a filter that excludes it should never see "Welcome".
    private var hasAnyContent: Bool {
        !games.isEmpty || !practices.isEmpty || !clips.isEmpty
    }

    /// Sport-aware noun for a single logged event — "Round" for golf, else
    /// "Game". Mirrors `Game.eventNoun`, but read from the athlete's pinned
    /// sport since the empty state has no Game to ask.
    private var eventNoun: String { activeSport == .golf ? "Round" : "Game" }

    /// The athlete's first name for the welcome line, or "" if unnamed.
    private var firstName: String {
        let trimmed = athlete.name.trimmingCharacters(in: .whitespaces)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    private func sportMatches(_ sport: Season.SportType?) -> Bool {
        guard let sport else { return true }   // seasonless passes through
        return sport == activeSport
    }

    /// The full reverse-chron feed, unfiltered. Drives both the displayed
    /// `entries` and the set of pills worth showing.
    private var allEntries: [JournalEntry] {
        JournalFeedBuilder.build(
            games: games,
            practices: practices,
            orphanClips: JournalFeedBuilder.orphans(from: clips),
            filter: .all
        )
    }

    private var entries: [JournalEntry] {
        allEntries.filter { filter.matches($0) }
    }

    /// Pills that actually have something to show — `.all` plus any sport/type
    /// filter that matches ≥1 entry. Never renders a filter that returns nothing
    /// (so a baseball athlete never sees a Golf pill, and Practices appears only
    /// once a practice exists).
    private var availableFilters: [JournalFilter] {
        let feed = allEntries
        return JournalFilter.allCases.filter { option in
            option == .all || feed.contains { option.matches($0) }
        }
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

                // Pills only earn their place once there's something to filter.
                // A brand-new athlete sees the welcome state instead — no point
                // offering a "Golf" filter over an empty page.
                if hasAnyContent {
                    PPFilterPillRow(
                        options: availableFilters,
                        title: { $0.title },
                        selection: $filter
                    )

                    if entries.isEmpty {
                        filteredEmptyState
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
                } else {
                    welcomeEmptyState
                }
            }
            .padding(.vertical, .spacingLarge)
        }
        .background(Theme.surface)
        .onChange(of: availableFilters) { _, newValue in
            // If the active pill no longer has any matching entries (e.g. the
            // last highlight was un-starred), fall back to All so the feed
            // doesn't strand on an empty filter whose pill has disappeared.
            if !newValue.contains(filter) { filter = .all }
        }
        .navigationTitle("The Journal.")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                PPAthleteSwitcher(athlete: athlete)
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

    // MARK: - Empty states

    /// New-user welcome — shown only when the athlete has no games, practices,
    /// or clips at all (no filter pills render above it). Names the athlete,
    /// adapts to sport, and offers the app's two first actions: record a clip
    /// (primary) or log a game/round (secondary).
    private var welcomeEmptyState: some View {
        VStack(spacing: .spacingMedium) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)

            VStack(spacing: .spacingXSmall) {
                Text(firstName.isEmpty ? "Welcome." : "Welcome, \(firstName).")
                    .font(.ppTitle2)
                    .foregroundStyle(Theme.textPrimary)
                Text("Your season starts here.")
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textSecondary)
                Text("Games, practices, clips, and milestones collect on this page.")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            VStack(spacing: .spacingSmall) {
                Button {
                    Haptics.medium()
                    NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill").font(.body)
                        Text("Record a Clip").font(.ppHeadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    NotificationCenter.default.post(name: .switchTab, object: MainTab.games.rawValue)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(.body)
                        Text("Log a \(eventNoun)").font(.ppHeadline)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().stroke(Theme.accent.opacity(0.5), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, .spacingSmall)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXLarge)
        .padding(.horizontal, .spacingLarge)
        .ppCard()
        .padding(.horizontal, 18)
        .padding(.top, 40)
    }

    /// Shown when the athlete HAS content but the active filter excluded all of
    /// it (e.g. tapping "Highlights" before starring a clip). The pills stay
    /// visible above so the user can step back to All.
    private var filteredEmptyState: some View {
        VStack(spacing: .spacingSmall) {
            Image(systemName: filteredEmptyIcon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text(filteredEmptyMessage)
                .font(.ppSubheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXLarge)
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    private var filteredEmptyMessage: String {
        switch filter {
        case .all:        return "Nothing here yet."
        case .games:      return "No \(eventNoun.lowercased())s logged yet."
        case .golf:       return "No golf rounds yet."
        case .practices:  return "No practices logged yet."
        case .highlights: return "No highlights yet — star a clip to add one."
        }
    }

    private var filteredEmptyIcon: String {
        switch filter {
        case .all:        return "tray"
        case .games:      return activeSport == .golf ? "figure.golf" : "baseball"
        case .golf:       return "figure.golf"
        case .practices:  return "figure.run"
        case .highlights: return "star"
        }
    }
}
