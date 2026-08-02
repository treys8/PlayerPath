//
//  JournalView.swift
//  PlayerPath
//
//  Visual overhaul — the Journal landing tab.
//  A calm, reverse-chronological feed of the athlete's games, practices, and
//  standalone clips. A compact "Live Now" strip pins to the top when an
//  activity is live: tapping a card opens its detail screen, and the card's own
//  pills run the activity in place (Score Hole / Record / End) via the shared
//  `LiveActivityController`. Filter pills scope the feed: All / Games / Golf /
//  Highlights.
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
    /// Drives the distinct "Coach Feedback" feed cards. Reading `recentNotifications`
    /// here re-resolves the feedback items whenever a `.coachComment` arrives —
    /// no schema/sync changes; the timestamp + videoID come from the notification.
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    private var activeSport: Season.SportType { athlete.sportType }

    @State private var filter: JournalFilter = .all

    /// Windowing cap for the feed — grows one page at a time as the user scrolls
    /// near the bottom (infinite scroll, mirrors VideoClipsViewModel.displayLimit).
    /// Resets on filter change; an athlete switch resets it for free because
    /// MainTabView applies `.id(...)` to JournalView, recreating all @State.
    @State private var displayLimit = pageSize
    private static let pageSize = 50

    /// Drives the Home search sheet — the app's single advanced-search surface
    /// (`AdvancedSearchView`), previously reachable only from the Videos tab.
    /// Promoting it here makes search discoverable from the landing screen;
    /// athlete profiles are single-sport, so this stays sport-scoped for free.
    @State private var showingSearch = false

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

    /// Photo-group row tapped in the feed — drives the day-scoped photo grid sheet.
    /// Nil = closed. Keyed by day so re-tapping the same group is idempotent.
    @State private var selectedPhotoDay: JournalPhotoDay?

    /// Score / End / Record behavior for the live strip's cards, shared with
    /// DashboardView so both surfaces drive a live activity identically. Owns the
    /// in-flight end spinners, the hole-scoring sheet target, and the recorder
    /// cover targets.
    @State private var live = LiveActivityController()

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
        // Resolve coach-feedback notifications to local clips up front so we can
        // both surface them as distinct cards AND suppress the plain orphan-clip
        // card for the same clip (the feedback card is the richer surface). Runs
        // once per body — keep it off the per-row path to preserve scroll perf.
        let feedbackItems = CoachFeedbackFeedItem.resolve(
            notifications: activityNotifService.recentNotifications,
            clips: clips
        )
        let clipsWithFeedback = Set(feedbackItems.map { $0.clip.id })
        let orphanClips = JournalFeedBuilder.orphans(from: clips)
            .filter { !clipsWithFeedback.contains($0.id) }

        return JournalFeedBuilder.build(
            games: games.filter { !$0.isLive },
            practices: practices.filter { !$0.isLive },
            orphanClips: orphanClips,
            orphanPhotos: orphanPhotos,
            coachFeedback: feedbackItems,
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

    /// Memoization box for the milestone index. A plain class held in @State (not
    /// a @State value) because it's written DURING body: mutating a reference
    /// type's property there is legal and — deliberately — triggers no re-render.
    /// That's safe: the cached index only changes when its inputs changed, and
    /// that input change is what caused this very render.
    private final class MilestoneCache {
        var token: Int?
        var index: [UUID: Milestone] = [:]
    }
    @State private var milestoneCache = MilestoneCache()

    /// Highest-significance milestone per game across every season in the feed,
    /// resolved ONCE per body so each row does an O(1) lookup instead of scanning
    /// (and re-ranking) the full milestone list twice — once for the marker, once
    /// for the headline. Season-spanning milestones (nil `gameID`) are skipped:
    /// they don't anchor a single row. Pure compute (no Firestore).
    ///
    /// Memoized on a hash of exactly the inputs MilestoneEngine reads, so the
    /// full engine run (stats walk + sorting + string building per season) fires
    /// only when a milestone-relevant value actually changed — not on every
    /// filter tap / notification publish / @Query invalidation. The token pass
    /// is one cheap O(games) walk with no allocation.
    private func milestoneIndex() -> [UUID: Milestone] {
        var hasher = Hasher()
        for game in games {
            hasher.combine(game.id)
            // Season membership matters: the engine walks season.games, so
            // re-homing a game changes BOTH seasons' streaks/firsts/counts even
            // when the game's own fields are untouched.
            hasher.combine(game.season?.id)
            hasher.combine(game.date)
            hasher.combine(game.countsTowardStats)
            hasher.combine(game.opponent)
            // Presence sentinel: a skipped field-group would otherwise make
            // adjacent games' values ambiguous in the hash sequence.
            hasher.combine(game.gameStats != nil)
            if let gs = game.gameStats {
                hasher.combine(gs.hits); hasher.combine(gs.atBats)
                hasher.combine(gs.homeRuns); hasher.combine(gs.doubles)
                hasher.combine(gs.walks); hasher.combine(gs.hitByPitches)
            }
            if game.season?.sport == .golf {
                // `holes` gates isGolfRoundScored — editing 18→9 can flip a
                // round in/out of milestone eligibility with identical hole rows.
                hasher.combine(game.holes)
                for hole in game.holeScores ?? [] {
                    hasher.combine(hole.holeNumber); hasher.combine(hole.score); hasher.combine(hole.par)
                }
                // Covers the manual-total path too: effectiveTotalScore/Par fall
                // back to the round's entered totals when no holes are scored.
                hasher.combine(game.effectiveTotalScore)
                hasher.combine(game.effectivePar)
            }
        }
        let token = hasher.finalize()
        if milestoneCache.token == token { return milestoneCache.index }

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
        milestoneCache.token = token
        milestoneCache.index = index
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

        // Windowing: render only the first `displayLimit` rows and grow on scroll.
        // Filters/pills/empty-state above stay on the FULL feed; only the rendered
        // slice is capped. Sections are computed from the slice, so a partially
        // loaded month simply grows as more pages load.
        let windowedEntries = Array(visibleEntries.prefix(displayLimit))
        let hasMore = visibleEntries.count > displayLimit
        let loadMoreTriggerIDs: Set<String> = hasMore ? Set(windowedEntries.suffix(10).map(\.id)) : []
        let sections = JournalFeedSections.build(from: windowedEntries)

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
                        ForEach(sections) { section in
                            sectionHeader(section.title)
                            ForEach(section.entries) { entry in
                                // O(1) lookup of this row's milestone — no per-row scan.
                                entryCell(entry, milestone: entry.gameID.flatMap { milestonesByGame[$0] })
                                    .onAppear {
                                        // Infinite scroll: grow the window when one of
                                        // the last ~10 loaded rows appears.
                                        if loadMoreTriggerIDs.contains(entry.id) {
                                            displayLimit += Self.pageSize
                                        }
                                    }
                            }
                        }
                        if hasMore {
                            ProgressView()
                                .padding(.vertical, .spacingMedium)
                        }
                    }
                } else {
                    JournalEmptyState(
                        athlete: athlete,
                        onAdd: {
                            Haptics.medium()
                            showingAddSheet = true
                        },
                        onLogEvent: { startLogEventFlow() }
                    )
                }
            }
            .padding(.vertical, .spacingLarge)
        }
        .background(Theme.surface)
        .refreshable { await refreshFeed() }
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
        .sheet(item: $selectedPhotoDay) { selection in
            JournalPhotoDaySheet(athlete: athlete, day: selection.day, sport: selection.sport)
        }
        .fullScreenCover(item: $live.recordingGame) { game in
            DirectCameraRecorderView(athlete: athlete, game: game)
        }
        .fullScreenCover(item: $live.recordingPractice) { practice in
            DirectCameraRecorderView(athlete: athlete, practice: practice)
        }
        // "Score Hole X" from a live card — opens the same sheet the detail
        // screens use, on the hole the card labelled.
        .sheet(item: $live.scoreTarget) { target in
            switch target.parent {
            case .game(let game):
                HoleScoringSheet(game: game, holeNumber: target.holeNumber)
            case .practice(let practice):
                HoleScoringSheet(practice: practice, holeNumber: target.holeNumber)
            }
        }
        .sheet(isPresented: $showingSearch) {
            AdvancedSearchView(athlete: athlete)
        }
        .onChange(of: filters) { _, newValue in
            // If the active pill no longer has any matching entries (e.g. the
            // last highlight was un-starred), fall back to All so the feed
            // doesn't strand on an empty filter whose pill has disappeared.
            if !newValue.contains(filter) { filter = .all }
        }
        .onChange(of: filter) { _, _ in
            // A new filter is a fresh, shorter list — page it from the top so we
            // don't render an inflated window of an unrelated filter's rows.
            displayLimit = Self.pageSize
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                PPAthleteSwitcher(athlete: athlete)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
            // The add dialog + import pickers are wired on this view regardless
            // of feed state; without this button they were reachable only from
            // the empty state, leaving no add affordance once content exists.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.medium()
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to your journal")
            }
        }
    }

    // MARK: - Pull to refresh

    /// Pull-to-refresh: kick a full bidirectional sync so the feed picks up
    /// changes made elsewhere — new coach clips/feedback and edits from another
    /// device. Local creates already update reactively via the @Query feed, so
    /// this only matters for pulling DOWN remote state. The @Query arrays refresh
    /// themselves once sync writes into SwiftData, so there is nothing to reload
    /// here. (The invitations banner runs its own Firestore listener and is not
    /// driven by this.) Mirrors VideoClipsView.refreshVideos: a busy / signed-out
    /// sync is expected and swallowed.
    @MainActor
    private func refreshFeed() async {
        Haptics.light()
        guard user.firebaseAuthUid != nil else { return }
        do {
            try await SyncCoordinator.shared.syncAll(for: user)
        } catch is SyncCoordinatorError {
            // Already syncing or signed out — expected, ignore.
        } catch {
            ErrorHandlerService.shared.handle(error, context: "JournalView.refreshable", showAlert: false)
        }
    }

    // MARK: - Coach feedback

    /// Clears the unread dot for a tapped coach-feedback card by marking its
    /// source notification read. Fire-and-forget; the @Published change re-renders
    /// the feed. Keyed by the notification's videoID (the coach video doc ID),
    /// matching `ActivityNotificationService.markVideoRead`'s predicate.
    private func markFeedbackRead(_ item: CoachFeedbackFeedItem) {
        guard let uid = user.firebaseAuthUid, !uid.isEmpty else { return }
        Task { await activityNotifService.markVideoRead(videoID: item.videoID, forUserID: uid) }
    }

    // MARK: - Photo group

    /// Open the day-scoped photo grid for a tapped photo-group row. Keyed by the
    /// group's calendar day + season sport (every photo in the group shares both),
    /// so the sheet can re-query exactly that group's photos and stay live as
    /// they're deleted.
    private func openPhotoDay(_ photos: [Photo]) {
        Haptics.light()
        // `.distantPast` fallback (not `.now`) must match the grouping key in
        // JournalFeedBuilder.photoEntries / JournalEntry.id, so a photo with no
        // createdAt resolves to the same day the sheet then filters on.
        let day = photos.first?.createdAt ?? .distantPast
        selectedPhotoDay = JournalPhotoDay(
            day: Calendar.current.startOfDay(for: day),
            sport: photos.compactMap { $0.season?.sport }.first
        )
    }

    // MARK: - Log-event flow

    /// Switch to the Games tab and open its add flow — mirrors
    /// DashboardView.createNewGame: switch first, then (once the tab's nav stack
    /// has mounted) ask GamesView to present its add sheet. A bare tab switch alone
    /// would strand the user on the Games list with no add affordance triggered.
    private func startLogEventFlow() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .switchTab, object: MainTab.games.rawValue)
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: .presentAddGame, object: nil)
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

            // Tap opens detail; the card's own pills drive the activity without
            // leaving the Journal. Golf gets Score Hole (scoring is the on-course
            // action, and clip attribution depends on it), baseball gets Record —
            // the two never coexist on one card.
            ForEach(liveGames) { game in
                NavigationLink {
                    GameDetailView(game: game)
                } label: {
                    LiveGameCard(
                        game: game,
                        isEnding: live.isEnding(game),
                        onScore: game.season?.sport == .golf
                            ? { live.presentScoreHole(for: game) }
                            : nil,
                        onRecord: game.season?.sport == .golf
                            ? nil
                            : { live.recordInto(game: game, context: "JournalLiveRecord") },
                        onEnd: { live.endGame(game, in: modelContext) }
                    )
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
                    // lighter RANGE SESSION card (Record + End), practice rounds
                    // the fuller round card (Score Hole + End). Mirrors
                    // DashboardView's split; without it every live practice
                    // mislabels as "PRACTICE ROUND".
                    //
                    // The round card is the catch-all so a live practice of any
                    // other type still surfaces (Dashboard filters those rows out
                    // entirely, which can strand a live activity off-screen) — but
                    // Score Hole is offered only for a real practice round, since
                    // LiveHoleTracker returns nil for every other type and the CTA
                    // would do nothing.
                    Group {
                        if practice.practiceType == PracticeType.rangeSession.rawValue {
                            LiveRangeCard(
                                practice: practice,
                                isEnding: live.isEnding(practice),
                                onRecord: { live.recordInto(practice: practice, context: "JournalRangeRecord") },
                                onEnd: { live.endPractice(practice, in: modelContext) }
                            )
                        } else {
                            LiveGameCard(
                                practiceRound: practice,
                                isEnding: live.isEnding(practice),
                                onScore: practice.practiceType == PracticeType.practiceRound.rawValue
                                    ? { live.presentScoreHole(for: practice) }
                                    : nil,
                                // Filming a shot mid-round is as central as
                                // scoring one — the range card has offered this
                                // since it shipped; rounds were the gap.
                                onRecord: { live.recordInto(practice: practice, context: "JournalRoundRecord") },
                                onEnd: { live.endPractice(practice, in: modelContext) }
                            )
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

    /// The tappable feed row + its per-type tap surface. Extracted verbatim from
    /// the body so the sectioned, nested ForEach stays type-checkable.
    @ViewBuilder
    private func entryCell(_ entry: JournalEntry, milestone: Milestone?) -> some View {
        switch entry {
        case .clip(let clip):
            // Clips open in the immersive full-screen player as a cover — matching
            // every other entry point in the app — so the player's own ✕ is the
            // single dismiss control, with no stacked nav back chevron.
            Button { selectedClip = clip } label: { feedRow(entry, milestone: milestone) }
                .buttonStyle(.plain)
        case .photoGroup(let photos):
            // A day's set of photos opens a day-scoped grid sheet (no multi-photo
            // push surface exists), so a single photo-heavy day stays one feed card.
            Button { openPhotoDay(photos) } label: { feedRow(entry, milestone: milestone) }
                .buttonStyle(.plain)
        case .coachFeedback(let item):
            // Opens the clip in the same full-screen player as a regular clip card,
            // and clears the unread dot.
            Button {
                markFeedbackRead(item)
                selectedClip = item.clip
            } label: { feedRow(entry, milestone: milestone) }
                .buttonStyle(.plain)
        default:
            NavigationLink { destination(for: entry) } label: { feedRow(entry, milestone: milestone) }
                .buttonStyle(.plain)
        }
    }

    /// A lightweight date-section header ("This Week", "June 2026", …). Reuses the
    /// "Live Now" small-caps label idiom for visual consistency with the feed.
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).smallCapsLabel()
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, .spacingSmall)
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
        // Photo groups open the day-scoped grid as a sheet (see `selectedPhotoDay`),
        // not a push, so they never route through here either.
        case .photoGroup:      EmptyView()
        case .photo(let p):
            PhotoDetailView(photo: p) {
                PhotoPersistenceService().deletePhoto(p, context: modelContext)
                Haptics.light()
            }
        // Coach-feedback cards open the clip as a full-screen cover (see
        // `selectedClip`), not a push, so they never route through here.
        case .coachFeedback:   EmptyView()
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
                    startLogEventFlow()
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
        case .feedback:   return "No coach feedback yet."
        }
    }

    private var filteredEmptyIcon: String {
        switch filter {
        case .all:        return "tray"
        case .games:      return activeSport == .golf ? "figure.golf" : "baseball"
        case .practices:  return "figure.run"
        case .photos:     return "photo"
        case .highlights: return "star"
        case .feedback:   return "bubble.left.and.text.bubble.right"
        }
    }
}
