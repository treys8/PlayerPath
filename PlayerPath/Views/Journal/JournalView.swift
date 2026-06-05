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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    private var activeSport: Season.SportType { athlete.sportType }

    @State private var filter: JournalFilter = .all

    private let athleteID: UUID
    @Query private var games: [Game]
    @Query private var practices: [Practice]
    @Query private var clips: [VideoClip]
    @Query private var photos: [Photo]

    /// Drives the "Add a photo or video" action sheet and its two library
    /// pickers (video / photo). Inert outside the empty state.
    @State private var showingAddSheet = false
    @State private var videoImportTrigger = false
    @State private var photoImportTrigger = false

    /// Clip tapped in the feed, presented in the full-screen player (cover, not a
    /// push) so it matches how clips open everywhere else in the app.
    @State private var selectedClip: VideoClip?

    init(user: User, athlete: Athlete) {
        self.user = user
        self.athlete = athlete
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
        self._photos = Query(
            filter: #Predicate<Photo> { $0.athlete?.id == id },
            sort: [SortDescriptor(\Photo.createdAt, order: .reverse)]
        )
    }

    // MARK: - Derived data
    //
    // Everything below is a pure function of the @Query arrays. `body` computes
    // each ONCE per render and threads the result through, instead of re-deriving
    // it per reference (which previously ran the feed pipeline ~7× per body). Live
    // games/practices are filtered inline in `body`.

    /// Photos with no game/practice parent — the ones that earn their own feed
    /// row (parented photos surface as a count inside their game/practice).
    private var orphanPhotos: [Photo] {
        JournalFeedBuilder.orphans(from: photos)
    }

    /// Sport-aware noun for a single logged event — "Round" for golf, else
    /// "Game". Mirrors `Game.eventNoun`, but read from the athlete's pinned
    /// sport since the empty state has no Game to ask.
    private var eventNoun: String { activeSport == .golf ? "Round" : "Game" }

    /// Pill label, sport-aware for the events pill: "Rounds" on a golf profile,
    /// "Games" otherwise. Every other pill keeps its static title. This is the
    /// only place the events pill is labelled, which is why there is no separate
    /// Golf pill — on a golf profile the games ARE the rounds.
    private func pillTitle(_ filter: JournalFilter) -> String {
        switch filter {
        case .games: return activeSport == .golf ? "Rounds" : "Games"
        default:     return filter.title
        }
    }

    /// The athlete's first name for the welcome line, or "" if unnamed.
    private var firstName: String {
        let trimmed = athlete.name.trimmingCharacters(in: .whitespaces)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    private func sportMatches(_ sport: Season.SportType?) -> Bool {
        guard let sport else { return true }   // seasonless passes through
        return sport == activeSport
    }

    /// The full reverse-chron feed for the profile's pinned sport, unfiltered by
    /// pill. Scoped to `activeSport` (seasonless clips/photos pass through) so a
    /// baseball profile never surfaces golf entries — and therefore never shows a
    /// golf pill. Mirrors the sport scoping the live strip already applies above.
    /// Drives the displayed entries, the pills worth showing, AND the welcome-vs-
    /// content decision (a profile carrying only stray off-sport data still reads
    /// as new and shows the welcome state, not an empty pill-less feed). Live
    /// games/practices are excluded here: they appear only in the pinned live
    /// strip, never as a duplicate feed row — so they never inflate the pills or
    /// the content check. Computed once per body.
    private func buildFeed() -> [JournalEntry] {
        JournalFeedBuilder.build(
            games: games.filter { !$0.isLive },
            practices: practices.filter { !$0.isLive },
            orphanClips: JournalFeedBuilder.orphans(from: clips),
            orphanPhotos: orphanPhotos,
            filter: .all
        )
        .filter { sportMatches($0.sport) }
    }

    /// Pills that actually have something to show — `.all` plus any content-type
    /// filter (Games, Practices, Photos, Highlights) that matches ≥1 entry. Never
    /// renders a filter that returns nothing, so Practices appears only once a
    /// practice exists and Photos only once a standalone photo does. Because the
    /// feed is sport-scoped upstream, no golf entry reaches a baseball profile —
    /// which is what keeps the (now-removed) Golf pill from ever reappearing.
    /// Takes the already-built feed so the body never re-derives it.
    private func availableFilters(from feed: [JournalEntry]) -> [JournalFilter] {
        JournalFilter.allCases.filter { option in
            option == .all || feed.contains { option.matches($0) }
        }
    }

    /// Highest-significance milestone per game across every season in the feed,
    /// resolved ONCE per body so each row does an O(1) lookup instead of scanning
    /// (and re-ranking) the full milestone list twice — once for the marker, once
    /// for the headline. Season-spanning milestones (nil `gameID`) are skipped:
    /// they don't anchor a single row. Pure compute (no Firestore).
    private func milestoneIndex() -> [UUID: Milestone] {
        var seenSeasonIDs = Set<UUID>()
        var index: [UUID: Milestone] = [:]
        for game in games {
            guard let season = game.season,
                  seenSeasonIDs.insert(season.id).inserted else { continue }
            for milestone in MilestoneEngine.milestones(for: season) {
                guard let gameID = milestone.gameID else { continue }
                if let existing = index[gameID],
                   existing.kind.sortRank >= milestone.kind.sortRank { continue }
                index[gameID] = milestone
            }
        }
        return index
    }

    // MARK: - Body

    var body: some View {
        // Derive everything ONCE per render and thread it through. Previously each
        // of these was a computed property re-evaluated on every reference, so a
        // single body ran the feed pipeline ~7× and re-scanned milestones per row.
        let liveGames = games.filter { $0.isLive && sportMatches($0.season?.sport) }
        let livePractices = practices.filter { $0.isLive && sportMatches($0.season?.sport) }
        let hasLiveActivity = !liveGames.isEmpty || !livePractices.isEmpty

        let feed = buildFeed()
        let hasContent = !feed.isEmpty
        let visibleEntries = feed.filter { filter.matches($0) }
        let filters = availableFilters(from: feed)
        let milestonesByGame = milestoneIndex()

        return ScrollView {
            LazyVStack(spacing: .spacingLarge) {
                // Pending coach invitations — self-hides when none. Ported from
                // the retired DashboardView: the home tab carries an invitation
                // tab badge (InvitationBadgeModifier) but, without this banner,
                // there was no in-feed surface to actually accept/decline. Sits
                // above the live strip so a pending invite is the first thing
                // seen, including for a brand-new athlete with no content yet.
                AthleteInvitationsBanner()
                    .padding(.horizontal, 18)

                if hasLiveActivity {
                    liveStrip(games: liveGames, practices: livePractices)
                }

                // Pills only earn their place once there's something to filter.
                // A brand-new athlete sees the welcome state instead — no point
                // offering a "Golf" filter over an empty page.
                if hasContent {
                    PPFilterPillRow(
                        options: filters,
                        title: pillTitle,
                        selection: $filter
                    )

                    if visibleEntries.isEmpty {
                        filteredEmptyState
                    } else {
                        ForEach(visibleEntries) { entry in
                            // O(1) lookup of this row's milestone — no per-row scan.
                            let milestone = entry.gameID.flatMap { milestonesByGame[$0] }
                            if case .clip(let clip) = entry {
                                // Clips open in the immersive full-screen player as
                                // a cover — matching every other entry point in the
                                // app — so the player's own ✕ is the single dismiss
                                // control, with no stacked nav back chevron.
                                Button { selectedClip = clip } label: { feedRow(entry, milestone: milestone) }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink { destination(for: entry) } label: { feedRow(entry, milestone: milestone) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    JournalEmptyState(
                        athlete: athlete,
                        onAdd: {
                            Haptics.medium()
                            showingAddSheet = true
                        },
                        onLogEvent: {
                            Haptics.light()
                            NotificationCenter.default.post(
                                name: .switchTab,
                                object: MainTab.games.rawValue
                            )
                        }
                    )
                }
            }
            .padding(.vertical, .spacingLarge)
        }
        .background(Theme.surface)
        // The empty state carries its own in-body serif title block, so suppress
        // the large nav title there — otherwise "The Journal." renders twice.
        .navigationTitle(hasContent ? "The Journal." : "")
        .navigationBarTitleDisplayMode(hasContent ? .large : .inline)
        .confirmationDialog("Add to your journal", isPresented: $showingAddSheet, titleVisibility: .visible) {
            Button("Record a Video") {
                NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
            }
            Button("Choose Videos") { videoImportTrigger = true }
            Button("Choose Photos") { photoImportTrigger = true }
            Button("Cancel", role: .cancel) {}
        }
        .bulkImportAttach(athlete: athlete, trigger: $videoImportTrigger)
        .bulkPhotoImportAttach(athlete: athlete, trigger: $photoImportTrigger)
        .fullScreenCover(item: $selectedClip) { clip in
            VideoPlayerView(clip: clip)
        }
        .onChange(of: filters) { _, newValue in
            // If the active pill no longer has any matching entries (e.g. the
            // last highlight was un-starred), fall back to All so the feed
            // doesn't strand on an empty filter whose pill has disappeared.
            if !newValue.contains(filter) { filter = .all }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                PPAthleteSwitcher(athlete: athlete)
            }
        }
    }

    // MARK: - Live strip

    @ViewBuilder
    private func liveStrip(games liveGames: [Game], practices livePractices: [Practice]) -> some View {
        VStack(spacing: .spacingMedium) {
            HStack(spacing: 6) {
                Circle().fill(ppAccent).frame(width: 7, height: 7)
                Text("Live Now").smallCapsLabel(color: ppAccent)
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ForEach(livePractices) { practice in
                NavigationLink {
                    PracticeDetailView(practice: practice)
                } label: {
                    // Range sessions have no holes/scoring — they get the
                    // lighter RANGE SESSION card, practice rounds the fuller
                    // tournament-style card. Mirrors DashboardView's split;
                    // without it every live practice mislabels as "PRACTICE
                    // ROUND". Cards stay display-only here (no End/Score
                    // closures) — tap opens the detail, where End lives.
                    Group {
                        if practice.practiceType == PracticeType.rangeSession.rawValue {
                            LiveRangeCard(practice: practice)
                        } else {
                            LiveGameCard(practiceRound: practice)
                        }
                    }
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Feed rows

    /// One tappable card in the feed. Pinning the tap area to the card itself
    /// matters: without `.contentShape`, an eager NavigationLink in a LazyVStack
    /// claims a region that bleeds past its frame and — being a later (z-above)
    /// sibling — steals taps from the filter pills above it.
    private func feedRow(_ entry: JournalEntry, milestone: Milestone?) -> some View {
        JournalEntryRow(entry: entry, milestone: milestone)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for entry: JournalEntry) -> some View {
        switch entry {
        case .game(let g):     GameDetailView(game: g)
        case .practice(let p): PracticeDetailView(practice: p)
        // Clips are presented as a full-screen cover (see `selectedClip`), not a
        // push, so they never route through here.
        case .clip:            EmptyView()
        case .photo(let p):
            PhotoDetailView(photo: p) {
                PhotoPersistenceService().deletePhoto(p, context: modelContext)
                Haptics.light()
            }
        }
    }

    // MARK: - Empty states

    /// Plain new-user welcome — the calmer "reserve" empty state kept per spec in
    /// case the ghosted-preview (`JournalEmptyState`) ever tests as confusing.
    /// Swap the `else` branch in `body` back to this to fall back. Names the
    /// athlete, adapts to sport, and offers the two first actions.
    private var welcomeEmptyState: some View {
        VStack(spacing: .spacingMedium) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(ppAccent)

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
                    .background(Capsule().fill(ppAccent))
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
                    .foregroundStyle(ppAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().stroke(ppAccent.opacity(0.5), lineWidth: 1.5))
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
        case .practices:  return "No practices logged yet."
        case .photos:     return "No photos yet."
        case .highlights: return "No highlights yet — star a clip to add one."
        }
    }

    private var filteredEmptyIcon: String {
        switch filter {
        case .all:        return "tray"
        case .games:      return activeSport == .golf ? "figure.golf" : "baseball"
        case .practices:  return "figure.run"
        case .photos:     return "photo"
        case .highlights: return "star"
        }
    }
}
