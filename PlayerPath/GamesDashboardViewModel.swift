//
//  GamesDashboardViewModel.swift
//  PlayerPath
//
//  MVVM architecture for dashboard game management
//  Uses athlete relationships instead of FetchDescriptor for reliable updates
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class GamesDashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var recentGames: [Game] = []
    @Published private(set) var upcomingGames: [Game] = []
    @Published private(set) var recentVideos: [VideoClip] = []
    @Published private(set) var totalGames: Int = 0
    @Published private(set) var totalVideos: Int = 0
    @Published private(set) var totalHighlights: Int = 0
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private Properties

    private let athlete: Athlete
    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    // MARK: - Initialization

    init(athlete: Athlete, modelContext: ModelContext) {
        self.athlete = athlete
        self.modelContext = modelContext

        setupNotificationObservers()

        // Initial load
        Task {
            await refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        cancellables.removeAll()
    }

    // MARK: - Public Methods

    /// Refresh all dashboard data from athlete relationships
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        /*
        // SwiftData's ModelContext has no `refresh` API. If you need a fresh instance
        // from storage, re-fetch by persistent identifier. For now, use the current
        // in-memory relationships on `athlete` which are updated via notifications.
        */
        // Re-fetch a fresh Athlete instance to ensure relationships reflect latest saves.
        
        let currentAthlete = latestAthlete()

        // Use athlete relationships - more reliable than FetchDescriptor for newly created objects
        let athleteGames = currentAthlete.games ?? []
        let athleteVideos = currentAthlete.videoClips ?? []

        #if DEBUG
        print("🔄 Dashboard: Refreshed - \(athleteGames.count) games, \(athleteVideos.count) videos")
        #endif

        // Update published properties
        updateGames(athleteGames)
        updateVideos(athleteVideos)

        #if DEBUG
        print("✅ Refresh complete. totalGames: \(totalGames)")
        #endif
    }

    /// Force refresh - useful for pull-to-refresh
    func forceRefresh() async {
        await refresh()
    }

    /// Start automatic refresh timer (every 3 seconds while view is visible)
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    /// Stop automatic refresh timer
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Private Methods

    private func latestAthlete() -> Athlete {
        // Re-fetch by persistent identifier to avoid stale relationship caches
        let id = athlete.persistentModelID
        var descriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        descriptor.fetchLimit = 1
        if let fetched = try? modelContext.fetch(descriptor).first {
            return fetched
        }
        return athlete
    }

    private func setupNotificationObservers() {
        let notifications: [Notification.Name] = [
            Notification.Name("GameCreated"),
            Notification.Name("GameBecameLive"),
            Notification.Name("VideoRecorded")
        ]

        for notificationName in notifications {
            NotificationCenter.default.publisher(for: notificationName)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        await self.refresh()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func updateGames(_ games: [Game]) {
        let now = Date()

        // Live games are driven by DashboardView's @Query; this VM handles recent/upcoming and totals.

        // Recent games (past, not live, not complete, limited to 3)
        recentGames = games
            .filter { game in
                guard !game.isLive, !game.isComplete else { return false }
                guard let date = game.date else { return false }
                return date <= now
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else {
                    return lhs.date != nil
                }
                return lhsDate > rhsDate
            }
            .prefix(3)
            .map { $0 }

        // Upcoming games (future, not live, not complete, limited to 3)
        upcomingGames = games
            .filter { game in
                guard !game.isLive, !game.isComplete else { return false }
                guard let date = game.date else { return false }
                return date > now
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else {
                    return lhs.date != nil
                }
                return lhsDate < rhsDate
            }
            .prefix(3)
            .map { $0 }

        totalGames = games.count
    }

    private func updateVideos(_ videos: [VideoClip]) {
        // Sort by creation date, most recent first
        let sortedVideos = videos.sorted { lhs, rhs in
            guard let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt else {
                return lhs.createdAt != nil
            }
            return lhsDate > rhsDate
        }

        recentVideos = Array(sortedVideos.prefix(3))
        totalVideos = videos.count
        totalHighlights = videos.filter { $0.isHighlight }.count
    }
}

