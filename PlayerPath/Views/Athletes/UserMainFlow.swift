//
//  UserMainFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "UserMainFlow")

struct UserMainFlow: View {
    let user: User
    let isNewUserFlag: Bool
    let hasCompletedOnboarding: Bool
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var sharedFolderManager: SharedFolderManager { .shared }
    @State private var selectedAthlete: Athlete?
    @State private var showCreationToast = false
    @State private var showingAthleteSelection = false
    @State private var hasRestoredSelection = false
    private let userID: UUID

    // Post-event highlight-reel banner: presents the stitched reel (Plus) or the
    // paywall (free) when the banner is tapped. State is set in handleReelBannerTap.
    @State private var showingReel = false
    @State private var showingReelPaywall = false
    @State private var reelClips: [VideoClip] = []
    @State private var reelScope = ""
    @State private var reelTitle = ""

    // NotificationCenter observer management using StateObject
    @StateObject private var notificationManager = NotificationObserverManager()

    // Activity notification service (Firestore-backed in-app notifications)
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    // Suppress the in-app banner when the user has disabled that activity stream.
    // Defaults true preserve the existing behavior for users who haven't opted out.
    @AppStorage(NotificationPrefKeys.coachActivity) private var coachActivity = true
    @AppStorage(NotificationPrefKeys.athleteActivity) private var athleteActivity = true

    // Quick Actions manager
    @ObservedObject private var quickActionsManager = QuickActionsManager.shared

    // App Intents (Siri/Shortcuts) hand-off. Replayed cold-launch-safe below.
    @ObservedObject private var intentBridge = IntentNavigationBridge.shared

    // StoreKit win-back: drives the cancellation-reason sheet when the user's
    // subscription is in grace period or billing retry.
    @ObservedObject private var storeKitManager = StoreKitManager.shared

    // Onboarding (tutorial shown from MainTabView after setup is complete)

    init(user: User, isNewUserFlag: Bool, hasCompletedOnboarding: Bool) {
        self.user = user
        self.isNewUserFlag = isNewUserFlag
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userID = user.id
    }

    // Helper for athlete selection persistence (user-specific)
    private var lastSelectedAthleteID: String? {
        get {
            UserDefaults.standard.string(forKey: "lastSelectedAthleteID_\(userID.uuidString)")
        }
        nonmutating set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: "lastSelectedAthleteID_\(userID.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedAthleteID_\(userID.uuidString)")
            }
        }
    }

    private var athletesForUser: [Athlete] {
        // Filter safely in Swift to avoid force unwrap in predicate
        allAthletes.filter { athlete in
            athlete.user?.id == userID
        }
    }

    private var resolvedAthlete: Athlete? {
        selectedAthlete ?? athletesForUser.first
    }

    var body: some View {
        Group {
            // IMPORTANT: Check if user is a coach FIRST before any athlete logic
            if authManager.userRole == .coach {
                CoachTabView()
                    .onAppear {
                    }
            }
            // Show athlete selection if user explicitly requested it via "Manage Athletes"
            else if showingAthleteSelection {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager,
                    onDismiss: {
                        showingAthleteSelection = false
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            // After athlete exists but no seasons - show season creation
            else if let athlete = resolvedAthlete,
                    isNewUserFlag,
                    (athlete.seasons ?? []).isEmpty {
                OnboardingSeasonCreationView(athlete: athlete)
                    .onAppear {
                    }
            }
            // After season exists but still new user - show backup preference
            else if let athlete = resolvedAthlete,
                    isNewUserFlag,
                    !(athlete.seasons ?? []).isEmpty {
                OnboardingBackupView(athlete: athlete)
                    .onAppear {
                    }
            }
            // Only check athlete-related logic if user is an athlete
            else if let athlete = resolvedAthlete {
                MainTabView(
                    user: user,
                    selectedAthlete: Binding(
                        get: { selectedAthlete ?? athlete },
                        set: { selectedAthlete = $0 }
                    )
                )
            } else if athletesForUser.isEmpty && isNewUserFlag {
                // New athletes need to create their first athlete profile
                AddAthleteView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    isFirstAthlete: true
                )
            } else if athletesForUser.isEmpty && (SyncCoordinator.shared.isSyncing || (!isNewUserFlag && SyncCoordinator.shared.lastSyncDate == nil)) {
                // Returning user on new device — sync is downloading their athletes,
                // or sync hasn't started yet (lastSyncDate is nil).
                // Show loading instead of AddAthleteView to prevent duplicate creation.
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Syncing your data...")
                        .font(.bodyMedium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if athletesForUser.isEmpty {
                // Returning user with no athletes after sync finished — let them add one
                AddAthleteView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    isFirstAthlete: true
                )
            } else {
                // Fallback: @Query hasn't populated yet — show loading briefly
                ProgressView("Loading athletes...")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingAthleteSelection)
        .sheet(item: Binding(
            get: { storeKitManager.winBackOpportunity },
            // SwiftUI calls set(nil) ONLY on interactive (swipe-down) dismissal.
            // Button paths clear the opportunity directly via dismissWinBackOpportunity(),
            // which propagates through get() — set is not invoked, so no double-logging.
            set: { newValue in
                if newValue == nil, let opp = storeKitManager.winBackOpportunity {
                    AnalyticsService.shared.trackWinBackDismissed(
                        productID: opp.productID,
                        tierName: opp.tierName,
                        reason: opp.reason.rawValue
                    )
                    storeKitManager.dismissWinBackOpportunity()
                }
            }
        )) { opportunity in
            WinBackSheet(opportunity: opportunity) { }
        }
        // Post-event highlight reel — presented from above the tab bar so it
        // works regardless of which tab is active when the banner is tapped.
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(clips: reelClips, scopeKey: reelScope, title: reelTitle)
        }
        .sheet(isPresented: $showingReelPaywall) {
            ImprovedPaywallView(user: user, requiredTier: .plus)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showCreationToast {
                    Text("Athlete created")
                        .font(.headingMedium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreationToast)
                }
                if let banner = activityNotifService.incomingBanner, shouldShowBanner(banner) {
                    ActivityNotificationBanner(notification: banner, onDismiss: {
                        // Banner dismissal (tap, X, or auto-timeout) does NOT mark the
                        // notification as read. Read state flips only on inbox row tap
                        // or when the athlete opens the specific video.
                        activityNotifService.dismissBanner()
                    }, onTap: {
                        handleActivityNotificationTap(banner)
                    })
                    .padding(.top, showCreationToast ? 0 : 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activityNotifService.incomingBanner?.id)
                }
                if let summary = HighlightReelBannerService.shared.pending {
                    HighlightReelBanner(
                        summary: summary,
                        onTap: { handleReelBannerTap(summary) },
                        onDismiss: { HighlightReelBannerService.shared.dismiss() }
                    )
                    .padding(.top, (showCreationToast || activityNotifService.incomingBanner != nil) ? 0 : 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: HighlightReelBannerService.shared.pending?.id)
                }
            }
        }
        .onChange(of: athletesForUser) { _, newValue in
            log.debug("Athletes changed for user \(user.id, privacy: .private) (\(user.email, privacy: .private)): \(newValue.count) athletes")
            for athlete in newValue {
                log.debug("  - \(athlete.name) (ID: \(athlete.id, privacy: .private), User: \(athlete.user?.email ?? "None", privacy: .private))")
            }

            // Clear selection if the selected athlete was deleted
            if let current = selectedAthlete, !newValue.contains(where: { $0.id == current.id }) {
                selectedAthlete = nil
            }

            // If a new athlete was created and we now have 2+ athletes, the newest one should already be selected
            // If exactly one athlete exists and none is selected, select it.
            if selectedAthlete == nil, newValue.count == 1, let only = newValue.first {
                log.debug("Auto-selecting only athlete: \(only.name) (ID: \(only.id, privacy: .private))")
                selectedAthlete = only
                // Only show the toast if the initial restoration has already run.
                // Otherwise this fires on every app launch when @Query populates
                // before .task restores the saved selection.
                if hasRestoredSelection {
                    showCreationToast = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1200))
                        showCreationToast = false
                    }
                }
            } else if let current = selectedAthlete {
                log.debug("Athletes changed. Current selection: \(current.name) (ID: \(current.id, privacy: .private))")
            }
        }
        .onAppear {
            setupNotificationObservers()
        }
        .task {
            log.debug("UserMainFlow task - User: \(user.id, privacy: .private), Athletes: \(athletesForUser.count)")

            // Restore last selected athlete from persistence
            if selectedAthlete == nil {
                if let savedID = lastSelectedAthleteID,
                   let savedUUID = UUID(uuidString: savedID),
                   let savedAthlete = athletesForUser.first(where: { $0.id == savedUUID }) {
                    log.debug("Restoring saved athlete: \(savedAthlete.name) (ID: \(savedAthlete.id, privacy: .private))")
                    selectedAthlete = savedAthlete
                } else if athletesForUser.count == 1, let only = athletesForUser.first {
                    log.debug("Task auto-selecting athlete: \(only.name) (ID: \(only.id, privacy: .private))")
                    selectedAthlete = only
                }
            }
            // Ensure SyncCoordinator knows which athlete to prioritise on launch
            if let athlete = selectedAthlete ?? athletesForUser.first {
                SyncCoordinator.shared.activeAthleteID = athlete.id.uuidString
            }
            hasRestoredSelection = true

            // Cold-launch hand-off: an App Intent may have set a pending action
            // before this view's .onChange was registered. Consume the initial
            // value here (after selection is restored so it lands on the right
            // profile). Warm-launch is handled by .onChange(of: intentBridge.pending).
            handleIntentAction()
        }
        .onChange(of: selectedAthlete) { _, newValue in
            // Persist athlete selection
            if let athlete = newValue {
                lastSelectedAthleteID = athlete.id.uuidString
                SyncCoordinator.shared.activeAthleteID = athlete.id.uuidString
                log.debug("Saved athlete selection: \(athlete.name) (ID: \(athlete.id, privacy: .private))")
            } else {
                lastSelectedAthleteID = nil
                SyncCoordinator.shared.activeAthleteID = nil
            }
        }
        .onChange(of: quickActionsManager.selectedQuickAction) { _, newAction in
            // Execute quick action when it changes
            if let action = newAction {
                log.info("Executing quick action: \(action.title)")
                quickActionsManager.executeAction(action)
            }
        }
        .onChange(of: intentBridge.pending) { _, newValue in
            // Warm launch: app already running when a Siri/Shortcuts intent fired.
            if newValue != nil { handleIntentAction() }
        }
    }

    // MARK: - App Intents Hand-off

    /// Replays a pending Siri/Shortcuts action onto the existing in-app
    /// NotificationCenter routes. Runs on the main actor from .task (cold
    /// launch) and .onChange (warm launch); `consume()` is idempotent so the
    /// two paths never double-fire.
    private func handleIntentAction() {
        // Wait until the selected profile is restored so the action lands on the
        // right athlete (record context / create-game scope).
        guard hasRestoredSelection else { return }
        guard let action = intentBridge.consume() else { return }

        switch action {
        case .recordClip:
            // Open the recorder for the selected athlete, attaching to its live
            // game/round (or live practice/range session) if one is in progress.
            // MainTabView's .presentVideoRecorder observer switches to the Videos
            // tab; VideoClipsView resolves the id in userInfo and binds context.
            guard let athlete = selectedAthlete ?? athletesForUser.first else { return }
            var userInfo: [String: String]? = nil
            if let gameID = athlete.games?.first(where: { $0.isLive })?.id {
                userInfo = ["gameId": gameID.uuidString]
            } else if let practiceID = athlete.practices?.first(where: { $0.isLive })?.id {
                userInfo = ["practiceId": practiceID.uuidString]
            }
            NotificationCenter.default.post(name: .presentVideoRecorder, object: nil, userInfo: userInfo)
            postSwitchTab(.videos)

        case .startGame(let athleteID):
            // Switch to the requested profile (if any) so GamesView re-scopes
            // sport-aware, then open its create-game/round screen.
            if let athleteID,
               let target = athletesForUser.first(where: { $0.id == athleteID }) {
                selectedAthlete = target
            }
            // Setting selectedAthlete re-keys (tears down + rebuilds) GamesView
            // via MainTabView's per-tab athlete id, which re-registers its
            // .presentAddGame observer. Wait one short hop (~15 frames, well
            // clear of the <50ms rebuild) so the fire-once post isn't dropped
            // in the rebuild gap. A no-op switch (same profile) is unaffected.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                postSwitchTab(.games)
                NotificationCenter.default.post(name: .presentAddGame, object: nil)
            }
        }
    }

    // MARK: - Activity Notification Tap Handling

    private func handleActivityNotificationTap(_ notification: ActivityNotification) {
        // Mark-read is handled by the banner's onDismiss closure; this only routes.
        ActivityNotificationRouter.route(notification, isCoach: authManager.userRole == .coach)
    }

    private func shouldShowBanner(_ banner: ActivityNotification) -> Bool {
        let isCoach = authManager.userRole == .coach
        switch banner.type {
        case .newVideo:
            return !isCoach || athleteActivity
        case .coachComment:
            return isCoach || coachActivity
        default:
            return true
        }
    }

    // MARK: - NotificationCenter Management

    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.showAthleteSelection) { _ in
            MainActor.assumeIsolated {
                showingAthleteSelection = true
            }
        }

        // Post-event highlight banner. Build the summary synchronously here (the
        // event already saved, so the relationship graph is settled) and never
        // hold the @Model past this call — see buildSummary. MainTabView's own
        // .gameEnded observer (weekly-summary refresh) is unrelated; two additive
        // observers on the same name are fine.
        notificationManager.observe(name: Notification.Name.gameEnded) { note in
            MainActor.assumeIsolated {
                guard let game = note.object as? Game else { return }
                if let summary = buildSummary(game: game) {
                    HighlightReelBannerService.shared.present(summary)
                }
            }
        }
        notificationManager.observe(name: Notification.Name.practiceEnded) { note in
            MainActor.assumeIsolated {
                guard let practice = note.object as? Practice else { return }
                if let summary = buildSummary(practice: practice) {
                    HighlightReelBannerService.shared.present(summary)
                }
            }
        }
    }

    // MARK: - Post-Event Highlight Banner

    /// Routes a banner tap by tier: Plus → present the stitched reel; free →
    /// paywall (the conversion nudge at the emotional peak). Resolves the
    /// snapshot's clip IDs to live clips at tap time (never held in the summary).
    private func handleReelBannerTap(_ summary: HighlightReelBannerService.Summary) {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            let byID = Dictionary(
                (resolvedAthlete?.videoClips ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            reelClips = summary.clipIDs.compactMap { byID[$0] }.filter { !$0.isDeleted }
            reelScope = summary.scopeKey
            reelTitle = summary.title
            showingReel = true
        } else {
            showingReelPaywall = true
        }
        HighlightReelBannerService.shared.dismiss()
    }

    /// Builds a banner summary for a just-ended game (or golf round). Fully
    /// synchronous: reads everything off the model in one pass and guards
    /// `isDeleted` so a delete racing the async notification delivery can't trap
    /// (feedback_swiftdata_model_access_across_await). Returns nil below the
    /// 2-highlight reel-eligibility threshold.
    private func buildSummary(game: Game) -> HighlightReelBannerService.Summary? {
        guard !game.isDeleted else { return nil }
        let eventID = game.id
        let isGolf = game.season?.sport == .golf
        let title: String = {
            guard let date = game.date else { return game.opponent.isEmpty ? "Game" : game.opponent }
            let d = DateFormatter.mediumDate.string(from: date)
            return game.opponent.isEmpty ? d : "\(game.opponent) · \(d)"
        }()

        if isGolf {
            guard let clipIDs = golfReelClipIDs(gameID: eventID, practiceID: nil,
                                                in: game.modelContext, allClips: game.videoClips ?? []),
                  clipIDs.count >= 2 else { return nil }
            return .init(id: eventID, eventKind: .round, scopeKey: "round_\(eventID.uuidString)",
                         title: title, clipIDs: clipIDs, count: clipIDs.count)
        } else {
            let clipIDs = highlightClipIDs(from: game.videoClips ?? [])
            guard clipIDs.count >= 2 else { return nil }
            return .init(id: eventID, eventKind: .game, scopeKey: "game_\(eventID.uuidString)",
                         title: title, clipIDs: clipIDs, count: clipIDs.count)
        }
    }

    /// Practice variant. Only golf practices go live (so `.practiceEnded` only
    /// fires for them), but the baseball branch is kept for safety.
    private func buildSummary(practice: Practice) -> HighlightReelBannerService.Summary? {
        guard !practice.isDeleted else { return nil }
        let eventID = practice.id
        let isGolf = practice.season?.sport == .golf
        let title: String = {
            let base = practice.course ?? (practice.practiceType == "range_session" ? "Range Session" : "Practice")
            guard let date = practice.date else { return base }
            return "\(base) · \(DateFormatter.mediumDate.string(from: date))"
        }()

        if isGolf {
            guard let clipIDs = golfReelClipIDs(gameID: nil, practiceID: eventID,
                                                in: practice.modelContext, allClips: practice.videoClips ?? []),
                  clipIDs.count >= 2 else { return nil }
            return .init(id: eventID, eventKind: .practice, scopeKey: "round_practice_\(eventID.uuidString)",
                         title: title, clipIDs: clipIDs, count: clipIDs.count)
        } else {
            let clipIDs = highlightClipIDs(from: practice.videoClips ?? [])
            guard clipIDs.count >= 2 else { return nil }
            return .init(id: eventID, eventKind: .practice, scopeKey: "practice_\(eventID.uuidString)",
                         title: title, clipIDs: clipIDs, count: clipIDs.count)
        }
    }

    /// Baseball/softball highlight set: the persisted `isHighlight` clips, ordered
    /// chronologically. Auto-curation already runs FREE at clip-save time
    /// (ClipPersistenceService: `isHighlight ||= shouldAutoHighlight(...)`, no tier
    /// gate), so the persisted flag already reaches free users — no recompute is
    /// needed. We deliberately do NOT re-derive "would-be" highlights here: that
    /// would re-promote clips the athlete manually un-starred (no flag distinguishes
    /// an auto-set true from a deliberate removal) and would write to the store
    /// inside a notification observer. Counting the flag keeps the banner, the reel,
    /// and the Highlights folder showing exactly the same set.
    private func highlightClipIDs(from clips: [VideoClip]) -> [UUID] {
        clips
            .filter { !$0.isDeleted && !$0.isDeletedRemotely && $0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .map { $0.id }
    }

    /// Golf curation lives in per-hole `HighlightReel` objects (birdie-or-better),
    /// not the `isHighlight` flag. Unions the round's reels' clips into one
    /// chronological set. `HighlightReel.clipIDs` are uuidStrings. Returns nil if
    /// the context is unavailable.
    private func golfReelClipIDs(gameID: UUID?, practiceID: UUID?,
                                 in context: ModelContext?, allClips: [VideoClip]) -> [UUID]? {
        guard let context else { return nil }
        let reels: [HighlightReel]
        do {
            // #Predicate can't equate optional UUIDs cleanly — fetch flat, filter
            // in memory (feedback_swiftdata_predicate_no_transforms).
            let all = try context.fetch(FetchDescriptor<HighlightReel>())
            reels = all.filter { reel in
                guard !reel.isDeletedRemotely else { return false }
                if let gameID { return reel.gameID == gameID }
                if let practiceID { return reel.practiceID == practiceID }
                return false
            }
        } catch {
            return nil
        }
        let wanted = Set(reels.flatMap { $0.clipIDs })
        guard !wanted.isEmpty else { return [] }
        return allClips
            .filter { !$0.isDeleted && !$0.isDeletedRemotely && wanted.contains($0.id.uuidString) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .map { $0.id }
    }
}
