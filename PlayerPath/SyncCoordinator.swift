//
//  SyncCoordinator.swift
//  PlayerPath
//
//  Core service for bidirectional Firestore sync
//  Syncs SwiftData models (Athletes, Seasons, Games, etc.) to Firestore for cross-device access
//
//  Entity sync is split across extension files:
//  SyncCoordinator+Athletes.swift, +Seasons.swift, +Games.swift, +Practices.swift,
//  +Videos.swift, +PracticeNotes.swift, +Photos.swift, +Coaches.swift
//

import Foundation
import SwiftData
import FirebaseAuth
import UIKit
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

/// Coordinates bidirectional sync between SwiftData (local) and Firestore (cloud)
/// Implements local-first architecture with background sync and conflict resolution
@MainActor
@Observable
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    // MARK: - Published State

    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncErrors: [SyncError] = []

    // MARK: - Active Athlete Scoping

    /// UUID string of the currently selected athlete. Set by UserMainFlow on
    /// selection change. Periodic (5-min) syncs only download videos for this
    /// athlete; full syncs (every 30 min, pull-to-refresh, launch) cover all.
    var activeAthleteID: String?

    // MARK: - Properties

    var modelContext: ModelContext?
    private var timer: Timer?
    /// Interval between full syncs that cover every athlete (30 minutes).
    private let fullSyncInterval: TimeInterval = 1800
    /// Tracks when the last full (all-athlete) sync completed so the periodic
    /// timer knows when to escalate from active-only to full sync.
    private var lastFullSyncDate: Date?
    /// Active background video/photo download tasks keyed by a local UUID so they
    /// can self-remove on completion and be bulk-cancelled on sign-out.
    var pendingDownloadTasks: [UUID: Task<Void, Never>] = [:]
    /// Tokens for background/foreground NotificationCenter observers so they
    /// can be removed before re-adding (avoids duplicates when configure() is
    /// called more than once).
    private var backgroundObservers: [Any] = []

    private init() {
    }

    // Note: As a @MainActor singleton, deinit cannot access isolated properties.
    // Timer and task cleanup is handled by stopPeriodicSync() called on sign-out.

    // MARK: - Configuration

    /// Configure the sync coordinator with a ModelContext.
    /// Safe to call multiple times — updates the context and restarts the timer
    /// without leaking additional timers.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Remove any previous background/foreground observers to avoid duplicates
        // when configure() is called more than once.
        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers.removeAll()

        // Pause the timer when the app enters background
        let bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timer?.invalidate()
                self?.timer = nil
            }
        }
        backgroundObservers.append(bgObserver)

        // Resume the timer when the app returns to foreground
        let fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startPeriodicSync()
            }
        }
        backgroundObservers.append(fgObserver)

        startPeriodicSync()
    }

    // MARK: - Comprehensive Sync (All Entities)

    /// Syncs all entities for a user in dependency order.
    /// Each step is isolated — a failure in one entity type does not abort the rest.
    /// Order: Athletes → Seasons → Games → Practices → Videos → PracticeNotes → Photos → Coaches
    /// Times out after 2 minutes to prevent isSyncing from staying true indefinitely.
    func syncAll(for user: User) async throws {
        guard !isSyncing else {
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let syncTask = Task { @MainActor in
            await self.isolatedSync("Athletes")  { try await self.syncAthletes(for: user) }
            await self.isolatedSync("Seasons")   { try await self.syncSeasons(for: user) }
            await self.isolatedSync("Games")     { try await self.syncGames(for: user) }
            await self.isolatedSync("Practices") { try await self.syncPractices(for: user) }
            await self.isolatedSync("Videos")    { try await self.syncVideos(for: user) }
            await self.isolatedSync("Notes")     { try await self.syncPracticeNotes(for: user) }
            await self.isolatedSync("Photos")    { try await self.syncPhotos(for: user) }
            await self.isolatedSync("Coaches")   { try await self.syncCoaches(for: user) }
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(120))
            syncTask.cancel()
        }

        // Wait for sync to finish (or be cancelled by timeout)
        await syncTask.value
        timeoutTask.cancel()

        if syncTask.isCancelled {
            syncLog.warning("syncAll timed out after 120 seconds")
            appendSyncError(SyncError(type: .syncFailed, entityId: "syncAll", message: "Sync timed out"))
        }

        lastSyncDate = Date()
    }

    /// Runs a sync step, recording any error without propagating it so sibling steps still run.
    private func isolatedSync(_ name: String, operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            appendSyncError(SyncError(type: .syncFailed, entityId: name, message: error.localizedDescription))
        }
    }

    /// Appends a sync error, capping the list at 100 entries to prevent unbounded growth.
    func appendSyncError(_ error: SyncError) {
        syncErrors.append(error)
        if syncErrors.count > 100 {
            syncErrors.removeFirst(syncErrors.count - 100)
        }
        // Bridge to centralized error tracking for analytics
        ErrorHandlerService.shared.handle(
            AppError.syncFailed(error.message),
            context: "SyncCoordinator.\(error.type)",
            showAlert: false
        )
    }

    // MARK: - Active-Athlete Sync

    /// Lightweight sync that uploads all dirty local data but only downloads
    /// videos for the active athlete. Notes, photos, and coaches are deferred
    /// to the next full sync. Used by the 5-minute periodic timer between full
    /// syncs to minimise Firestore reads and battery usage.
    func syncActiveAthlete(for user: User) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let syncTask = Task { @MainActor in
            // Upload paths are cheap — only dirty items are processed, so run
            // them for ALL athletes to keep local changes flowing to Firestore.
            await self.isolatedSync("Athletes")  { try await self.syncAthletes(for: user) }
            await self.isolatedSync("Seasons")   { try await self.syncSeasons(for: user) }
            await self.isolatedSync("Games")     { try await self.syncGames(for: user) }
            await self.isolatedSync("Practices") { try await self.syncPractices(for: user) }

            // Video download is the expensive per-athlete query — scope it.
            await self.isolatedSync("Videos")    { try await self.syncVideos(for: user, activeOnly: true) }
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(120))
            syncTask.cancel()
        }

        await syncTask.value
        timeoutTask.cancel()

        if syncTask.isCancelled {
            syncLog.warning("syncActiveAthlete timed out after 120 seconds")
            appendSyncError(SyncError(type: .syncFailed, entityId: "activeSync", message: "Active-athlete sync timed out"))
        }

        lastSyncDate = Date()
    }

    // MARK: - Background Sync

    private func startPeriodicSync() {
        timer?.invalidate() // Prevent multiple timers if configure() is called again
        timer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncInBackground()
            }
        }
    }

    private func syncInBackground() async {
        guard let context = modelContext else { return }

        guard let user = getCurrentUser(context: context) else {
            return
        }

        // Escalate to a full sync when enough time has passed (or on first run).
        let needsFullSync = lastFullSyncDate == nil
            || Date().timeIntervalSince(lastFullSyncDate!) > fullSyncInterval

        do {
            if needsFullSync {
                try await syncAll(for: user)
                lastFullSyncDate = Date()
            } else {
                try await syncActiveAthlete(for: user)
            }
        } catch {
            syncLog.error("Background sync failed: \(error.localizedDescription)")
            syncErrors.append(SyncError(
                type: .syncFailed,
                entityId: "background-sync",
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Helper Methods

    func getCurrentUser(context: ModelContext) -> User? {
        guard let firebaseEmail = Auth.auth().currentUser?.email else {
            return nil
        }

        // Predicate fetch — avoids loading all User rows into memory.
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in
                user.email == firebaseEmail
            }
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            syncLog.error("Failed to fetch current user: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes all local SwiftData records for the current user.
    /// Called on sign-out and account deletion to prevent data leakage between accounts.
    /// - Parameter fallbackContext: Used when SyncCoordinator hasn't been configured
    ///   (e.g. coach users who skip athlete sync setup).
    func clearLocalData(fallbackContext: ModelContext? = nil) {
        guard let context = modelContext ?? fallbackContext else {
            syncLog.warning("clearLocalData: no modelContext available")
            return
        }

        do {
            // Delete in dependency order (children first) to avoid orphan issues
            try context.delete(model: PlayResult.self)
            try context.delete(model: PracticeNote.self)
            try context.delete(model: GameStatistics.self)
            try context.delete(model: AthleteStatistics.self)
            try context.delete(model: Photo.self)
            try context.delete(model: VideoClip.self)
            try context.delete(model: PendingUpload.self)
            try context.delete(model: Game.self)
            try context.delete(model: Practice.self)
            try context.delete(model: Season.self)
            try context.delete(model: Coach.self)
            try context.delete(model: Athlete.self)
            try context.delete(model: OnboardingProgress.self)
            try context.delete(model: User.self)
            try context.save()
            lastSyncDate = nil
            syncLog.info("Cleared all local SwiftData records")
        } catch {
            syncLog.error("Failed to clear local data: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(error, context: "SyncCoordinator.clearLocalData", showAlert: false)
        }

        // Delete local video and photo files from disk
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            for folder in ["Clips", "Photos"] {
                let folderURL = documentsURL.appendingPathComponent(folder, isDirectory: true)
                if fileManager.fileExists(atPath: folderURL.path) {
                    do {
                        try fileManager.removeItem(at: folderURL)
                        syncLog.info("Deleted local \(folder) directory")
                    } catch {
                        syncLog.error("Failed to delete \(folder) directory: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Stops the periodic sync timer, removes background/foreground observers,
    /// and cancels any in-flight background downloads.
    func stopPeriodicSync() {
        timer?.invalidate()
        timer = nil
        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers.removeAll()
        pendingDownloadTasks.values.forEach { $0.cancel() }
        pendingDownloadTasks.removeAll()
    }
}

// MARK: - Supporting Types

/// Represents a sync error for UI display
struct SyncError: Identifiable {
    enum ErrorType {
        case uploadFailed
        case downloadFailed
        case conflictResolution
        case syncFailed
    }

    let id = UUID()
    let type: ErrorType
    let entityId: String
    let message: String
    let timestamp: Date = Date()
}
