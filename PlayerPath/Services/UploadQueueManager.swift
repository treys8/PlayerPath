//
//  UploadQueueManager.swift
//  PlayerPath
//
//  Manages automatic video upload queue with retry logic and background processing
//

import Foundation
import SwiftData
import Combine
import BackgroundTasks
import UIKit
import os

private let uploadLog = Logger(subsystem: "com.playerpath.app", category: "UploadQueue")

@MainActor
@Observable
final class UploadQueueManager {
    static let shared = UploadQueueManager()

    // Background task identifier
    static let backgroundTaskIdentifier = "com.playerpath.video-upload"

    // MARK: - Published State

    var pendingUploads: [QueuedUpload] = []
    var activeUploads: [UUID: Double] = [:] // clipId → progress
    var failedUploads: [QueuedUpload] = []
    var isProcessing: Bool = false

    // MARK: - Private State

    private var queueIsDirty = false
    private var notificationObservers: [Any] = []
    private var processingTask: Task<Void, Never>?
    private var retryTasks: [UUID: Task<Void, Never>] = [:] // clipId → retry sleep task
    private var backgroundBatchTask: Task<Void, Never>?
    private let maxConcurrentUploads = 2
    private let maxRetries = 10
    static let retryDelays: [TimeInterval] = [5, 15, 60, 120, 300, 600, 900, 1800, 3600] // 5s→15s→1m→2m→5m→10m→15m→30m→1hr

    private var modelContext: ModelContext?
    private var isConfigured = false
    private var cachedPreferences: UserPreferences?
    private var preferencesLastFetched: Date?

    private init() {}

    /// Configure the manager with a ModelContext (call once at app startup)
    func configure(modelContext: ModelContext) {
        guard !isConfigured else {
            return
        }

        self.modelContext = modelContext
        self.isConfigured = true

        // Restore persisted queue from database
        restoreQueueFromDatabase()

        setupNetworkMonitoring()

        // Start processing if there are pending uploads
        if !pendingUploads.isEmpty {
            startProcessing()
        }
    }

    /// Register background tasks (call from AppDelegate didFinishLaunching)
    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                UploadQueueManager.shared.handleBackgroundTask(processingTask)
            }
        }
    }

    /// Schedule background upload task
    func scheduleBackgroundUpload() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            uploadLog.error("Failed to schedule background upload task: \(error.localizedDescription)")
        }
    }

    /// Handle background task execution
    private func handleBackgroundTask(_ task: BGProcessingTask) {

        // Schedule next background task
        scheduleBackgroundUpload()

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingTask?.cancel()
                self.backgroundBatchTask?.cancel()
                await self.persistQueueToDatabase()
            }
        }

        // Process uploads — store the task so the expiration handler can cancel it
        backgroundBatchTask = Task { @MainActor in
            await processBackgroundBatch()

            // Persist state and complete
            await persistQueueToDatabase()
            task.setTaskCompleted(success: true)
            backgroundBatchTask = nil
        }
    }

    /// Process a limited batch of uploads for background execution
    private func processBackgroundBatch() async {
        guard let modelContext = modelContext else { return }

        // Process up to 3 uploads concurrently to maximize limited background time
        let batch = Array(pendingUploads.prefix(3))
        guard !batch.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for upload in batch {
                group.addTask { @MainActor in
                    await self.processUpload(upload, context: modelContext)
                }
            }
        }
    }

    private func setupNetworkMonitoring() {
        // Listen for network status changes
        let networkObserver = NotificationCenter.default.addObserver(
            forName: .networkStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Network changed - check if we should resume processing
                if !self.isProcessing && !self.pendingUploads.isEmpty {
                    self.startProcessing()
                }
            }
        }
        notificationObservers.append(networkObserver)

        // Listen for app going to background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Persist queue and schedule background task
                await self.persistQueueToDatabase()
                if !self.pendingUploads.isEmpty {
                    self.scheduleBackgroundUpload()
                }
            }
        }
        notificationObservers.append(backgroundObserver)

        // Listen for app becoming active
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Resume processing when app becomes active
                if !self.isProcessing && !self.pendingUploads.isEmpty {
                    self.startProcessing()
                }
            }
        }
        notificationObservers.append(activeObserver)
    }

    // MARK: - Queue Persistence

    /// Persist pending uploads to database for recovery after app restart
    func persistQueueToDatabase() async {
        guard queueIsDirty else { return }
        guard let modelContext = modelContext else {
            return
        }

        do {
            // Fetch existing persisted uploads
            let descriptor = FetchDescriptor<PendingUpload>()
            let existingUploads = try modelContext.fetch(descriptor)

            // Delete existing entries
            for upload in existingUploads {
                modelContext.delete(upload)
            }

            // Insert current pending uploads, yielding periodically to avoid blocking main thread
            let allUploads: [(QueuedUpload, PendingUploadStatus)] =
                pendingUploads.map { ($0, .pending) } + failedUploads.map { ($0, .failed) }

            for (index, (upload, status)) in allUploads.enumerated() {
                let persistedUpload: PendingUpload
                if upload.isCoachUpload, let folderID = upload.folderID,
                   let coachID = upload.coachID, let coachName = upload.coachName {
                    persistedUpload = PendingUpload(
                        clipId: upload.clipId,
                        fileName: upload.fileName,
                        filePath: upload.filePath,
                        priority: upload.priority.rawValue,
                        retryCount: upload.retryCount,
                        lastAttempt: upload.lastAttempt,
                        status: status,
                        folderID: folderID,
                        coachID: coachID,
                        coachName: coachName,
                        sessionID: upload.sessionID
                    )
                } else {
                    persistedUpload = PendingUpload(
                        clipId: upload.clipId,
                        athleteId: upload.athleteId ?? UUID(),
                        fileName: upload.fileName,
                        filePath: upload.filePath,
                        priority: upload.priority.rawValue,
                        retryCount: upload.retryCount,
                        lastAttempt: upload.lastAttempt,
                        status: status
                    )
                }
                modelContext.insert(persistedUpload)

                // Yield every 20 inserts to keep UI responsive
                if index > 0 && index % 20 == 0 {
                    await Task.yield()
                }
            }

            try modelContext.save()
            queueIsDirty = false
        } catch {
            uploadLog.error("Failed to persist upload queue to SwiftData: \(error.localizedDescription)")
        }
    }

    /// Restore pending uploads from database on app launch
    private func restoreQueueFromDatabase() {
        guard let modelContext = modelContext else {
            return
        }

        do {
            let descriptor = FetchDescriptor<PendingUpload>(
                sortBy: [SortDescriptor(\PendingUpload.createdAt, order: .forward)]
            )
            let persistedUploads = try modelContext.fetch(descriptor)

            // Restore to in-memory queues
            for persisted in persistedUploads {
                let queuedUpload: QueuedUpload

                if persisted.isCoachUpload, let folderID = persisted.folderID,
                   let coachID = persisted.coachID, let coachName = persisted.coachName {
                    // Coach upload — verify local file still exists
                    guard FileManager.default.fileExists(atPath: persisted.filePath) else {
                        modelContext.delete(persisted)
                        continue
                    }
                    queuedUpload = QueuedUpload(
                        clipId: persisted.clipId,
                        fileName: persisted.fileName,
                        filePath: persisted.filePath,
                        priority: UploadPriority(rawValue: persisted.priority) ?? .normal,
                        retryCount: persisted.retryCount,
                        lastAttempt: persisted.lastAttempt,
                        folderID: folderID,
                        coachID: coachID,
                        coachName: coachName,
                        sessionID: persisted.sessionID
                    )
                } else {
                    // Athlete upload — verify the video clip still exists
                    let clipIdToFind = persisted.clipId
                    let clipDescriptor = FetchDescriptor<VideoClip>(
                        predicate: #Predicate<VideoClip> { clip in
                            clip.id == clipIdToFind
                        }
                    )
                    guard let clip = try modelContext.fetch(clipDescriptor).first else {
                        modelContext.delete(persisted)
                        continue
                    }

                    // Skip if already uploaded
                    if clip.isUploaded {
                        modelContext.delete(persisted)
                        continue
                    }

                    queuedUpload = QueuedUpload(
                        clipId: persisted.clipId,
                        athleteId: persisted.athleteId,
                        fileName: persisted.fileName,
                        filePath: persisted.filePath,
                        priority: UploadPriority(rawValue: persisted.priority) ?? .normal,
                        retryCount: persisted.retryCount,
                        lastAttempt: persisted.lastAttempt
                    )
                }

                if persisted.status == PendingUploadStatus.failed {
                    failedUploads.append(queuedUpload)
                } else {
                    pendingUploads.append(queuedUpload)
                }

                // Delete persisted record (it's now in memory)
                modelContext.delete(persisted)
            }

            // Sort by priority
            pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }

            try modelContext.save()
        } catch {
            uploadLog.error("Failed to restore upload queue from database: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    /// Queues a video for upload
    func enqueue(_ clip: VideoClip, athlete: Athlete, priority: UploadPriority = .normal) {
        // Don't queue if already uploaded
        guard !clip.isUploaded else {
            return
        }

        // Don't queue if already in any queue (pending, active, or failed)
        guard !pendingUploads.contains(where: { $0.clipId == clip.id }),
              !failedUploads.contains(where: { $0.clipId == clip.id }),
              activeUploads[clip.id] == nil else {
            return
        }

        let upload = QueuedUpload(
            clipId: clip.id,
            athleteId: athlete.id,
            fileName: clip.fileName,
            filePath: clip.resolvedFilePath,
            priority: priority,
            retryCount: 0,
            lastAttempt: nil
        )

        pendingUploads.append(upload)
        pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }
        queueIsDirty = true


        // Trigger processing if not already running
        if !isProcessing {
            startProcessing()
        }
    }

    /// Queues a coach video for upload to a shared folder.
    /// Uses the same background task support, persistence, and retry logic as athlete uploads.
    func enqueueCoachUpload(
        fileName: String,
        filePath: String,
        folderID: String,
        coachID: String,
        coachName: String,
        sessionID: String? = nil,
        priority: UploadPriority = .normal
    ) {
        // Deterministic UUID from folderID+fileName so duplicate detection works across app restarts
        let clipId = Self.stableUUID(from: "\(folderID)|\(fileName)")

        // Don't queue if already in any queue
        guard !pendingUploads.contains(where: { $0.clipId == clipId }),
              !failedUploads.contains(where: { $0.clipId == clipId }),
              activeUploads[clipId] == nil else {
            return
        }

        let upload = QueuedUpload(
            clipId: clipId,
            fileName: fileName,
            filePath: filePath,
            priority: priority,
            retryCount: 0,
            lastAttempt: nil,
            folderID: folderID,
            coachID: coachID,
            coachName: coachName,
            sessionID: sessionID
        )

        pendingUploads.append(upload)
        pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }
        queueIsDirty = true

        if !isProcessing {
            startProcessing()
        }
    }

    /// Manually retry a failed upload
    func retryFailed(_ upload: QueuedUpload) {
        failedUploads.removeAll { $0.clipId == upload.clipId }

        var retryUpload = upload
        retryUpload.retryCount = 0
        retryUpload.lastAttempt = nil

        pendingUploads.append(retryUpload)
        pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }
        queueIsDirty = true

    }

    /// Cancels a pending upload
    func cancel(_ clipId: UUID) {
        pendingUploads.removeAll { $0.clipId == clipId }
        activeUploads.removeValue(forKey: clipId)
        queueIsDirty = true
    }

    /// Clears all failed uploads and their associated retry tasks
    func clearFailed() {
        for upload in failedUploads {
            retryTasks[upload.clipId]?.cancel()
            retryTasks.removeValue(forKey: upload.clipId)
        }
        failedUploads.removeAll()
        queueIsDirty = true
    }

    /// Clears all upload queues - call on logout or account switch
    func clearAllQueues() {
        // Stop any active processing
        processingTask?.cancel()
        processingTask = nil
        backgroundBatchTask?.cancel()
        backgroundBatchTask = nil

        // Cancel all pending retry tasks so they don't resurrect uploads
        for (_, task) in retryTasks {
            task.cancel()
        }
        retryTasks.removeAll()

        // Clear in-memory queues
        pendingUploads.removeAll()
        failedUploads.removeAll()
        activeUploads.removeAll()
        isProcessing = false
        queueIsDirty = true

        // Clear persisted records from database
        guard let modelContext = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<PendingUpload>()
            let persistedUploads = try modelContext.fetch(descriptor)

            for upload in persistedUploads {
                modelContext.delete(upload)
            }

            try modelContext.save()
        } catch {
            uploadLog.error("Failed to clear upload queue from database: \(error.localizedDescription)")
        }
    }

    /// Cancel all queued uploads for a specific athlete (e.g., on athlete deletion)
    func cancelUploads(forAthleteId athleteId: UUID) {
        // Cancel retry tasks for matching clips
        let matchingPending = pendingUploads.filter { $0.athleteId == athleteId }
        for upload in matchingPending {
            retryTasks[upload.clipId]?.cancel()
            retryTasks[upload.clipId] = nil
        }

        pendingUploads.removeAll { $0.athleteId == athleteId }
        failedUploads.removeAll { $0.athleteId == athleteId }
        queueIsDirty = true
    }

    /// Cancel all queued coach uploads for a specific folder
    func cancelCoachUploads(forFolderID folderID: String) {
        let matching = pendingUploads.filter { $0.folderID == folderID }
        for upload in matching {
            retryTasks[upload.clipId]?.cancel()
            retryTasks[upload.clipId] = nil
        }

        pendingUploads.removeAll { $0.folderID == folderID }
        failedUploads.removeAll { $0.folderID == folderID }
        queueIsDirty = true
    }

    /// Gets total pending upload count
    var totalPendingCount: Int {
        pendingUploads.count
    }

    /// Gets upload progress for a specific clip
    func getProgress(for clipId: UUID) -> Double? {
        activeUploads[clipId]
    }

    // MARK: - Processing

    private func startProcessing() {
        processingTask?.cancel()

        processingTask = Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            while !Task.isCancelled && !pendingUploads.isEmpty {
                // Process up to maxConcurrentUploads at a time
                await processNextBatch()

                // Small delay between batches
                try? await Task.sleep(for: .milliseconds(500))
            }

        }
    }

    private func processNextBatch() async {
        guard let modelContext = getModelContext() else {
            return
        }

        // Check network conditions (cache preferences to avoid fetching every 0.5s)
        let networkMonitor = ConnectivityMonitor.shared
        let now = Date()
        if cachedPreferences == nil || preferencesLastFetched.map({ now.timeIntervalSince($0) > 30 }) != false {
            let descriptor = FetchDescriptor<UserPreferences>()
            do {
                cachedPreferences = try modelContext.fetch(descriptor).first
            } catch {
                uploadLog.error("Failed to fetch UserPreferences for network policy: \(error.localizedDescription)")
            }
            preferencesLastFetched = now
        }
        let preferences = cachedPreferences

        guard networkMonitor.shouldAllowUploads(preferences: preferences) else {
            if !networkMonitor.isConnected {
            } else if networkMonitor.connectionType == .cellular && !(preferences?.allowCellularUploads ?? false) {
            }
            return
        }

        // Get next uploads to process
        let activeCount = activeUploads.count
        let availableSlots = maxConcurrentUploads - activeCount
        let nextUploads = Array(pendingUploads.prefix(availableSlots))

        // Process each upload concurrently
        await withTaskGroup(of: Void.self) { group in
            for upload in nextUploads {
                group.addTask { @MainActor in
                    await self.processUpload(upload, context: modelContext)
                }
            }
        }
    }

    private func processUpload(_ upload: QueuedUpload, context: ModelContext) async {
        // Remove from pending
        pendingUploads.removeAll { $0.clipId == upload.clipId }
        queueIsDirty = true

        // Mark as active
        activeUploads[upload.clipId] = 0.0

        let uploadStartTime = Date()

        // Progress monitoring task — declared before do/catch so it can be
        // cancelled on both success and failure paths.
        var progressTask: Task<Void, Never>?

        // Track reserved bytes so they can be released on failure
        var reservedBytes: Int64 = 0
        weak var quotaUser: User?

        do {
            // Coach uploads follow a separate path — no local VideoClip or Athlete
            if upload.isCoachUpload {
                try await processCoachUpload(upload)
                progressTask?.cancel()
                progressTask = nil
                activeUploads.removeValue(forKey: upload.clipId)
                return
            }

            // Fetch VideoClip and Athlete from database
            guard let athleteId = upload.athleteId else {
                throw UploadError.uploadFailed("Missing athleteId for non-coach upload")
            }
            guard let clip = try fetchVideoClip(upload.clipId, context: context),
                  let athlete = try fetchAthlete(athleteId, context: context) else {
                throw UploadError.entityNotFound
            }

            // Enforce per-tier cloud storage limit before uploading.
            // Reserve bytes optimistically to prevent concurrent uploads from
            // both passing the quota check before either finishes.
            if let user = athlete.user {
                let fileSize = FileManager.default.fileSize(atPath: upload.filePath)
                let tier = StoreKitManager.shared.currentTier
                let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
                let projectedUsage = user.cloudStorageUsedBytes + fileSize
                if projectedUsage > limitBytes {
                    let usedGB = Double(user.cloudStorageUsedBytes) / StorageConstants.bytesPerGBDouble
                    throw UploadError.storageLimitExceeded(usedGB: usedGB, limitGB: tier.storageLimitGB)
                }
                // Reserve space now; released on failure or kept on success
                user.cloudStorageUsedBytes += fileSize
                reservedBytes = fileSize
                quotaUser = user
            }

            // Compress video before upload to reduce bandwidth and storage costs.
            // Non-fatal: if compression fails, upload the original file.
            do {
                let sourceURL = URL(fileURLWithPath: upload.filePath)
                _ = try await VideoCompressionService.shared.compressForUpload(at: sourceURL)

                // Update reserved quota with actual (possibly compressed) size
                if let user = quotaUser {
                    let compressedSize = FileManager.default.fileSize(atPath: upload.filePath)
                    let savedBytes = reservedBytes - compressedSize
                    if savedBytes > 0 {
                        user.cloudStorageUsedBytes -= savedBytes
                        reservedBytes = compressedSize
                    }
                }
            } catch {
                uploadLog.warning("Video compression failed, uploading original: \(error.localizedDescription)")
            }

            // Perform upload with progress updates
            let cloudManager = VideoCloudManager.shared

            // Start progress monitor BEFORE the upload so UI gets incremental updates
            progressTask = Task { @MainActor in
                while activeUploads[upload.clipId] != nil && !Task.isCancelled {
                    if let progress = cloudManager.uploadProgress[upload.clipId] {
                        activeUploads[upload.clipId] = progress
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            // 10-minute timeout prevents stalled uploads from hanging indefinitely
            let cloudURL = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await cloudManager.uploadVideo(clip, athlete: athlete)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(600)) // 10 minutes
                    throw UploadError.uploadFailed("Upload timed out after 10 minutes")
                }
                guard let result = try await group.next() else {
                    throw UploadError.uploadFailed("No upload result received")
                }
                group.cancelAll()
                return result
            }

            // Save metadata to Firestore BEFORE marking local state as uploaded.
            // This ensures we never have isUploaded=true without valid Firestore metadata.
            do {
                try await cloudManager.saveVideoMetadataToFirestore(clip, athlete: athlete, downloadURL: cloudURL)
            } catch {
                // Firestore write failed — rollback the Storage file to prevent orphans
                do {
                    try await cloudManager.deleteAthleteVideo(fileName: upload.fileName)
                } catch {
                    uploadLog.error("Failed to rollback Storage file '\(upload.fileName)' after Firestore failure: \(error.localizedDescription)")
                }

                // Release reserved storage quota and zero out so the outer catch
                // block doesn't double-release via reservedBytes
                if let user = athlete.user {
                    user.cloudStorageUsedBytes = max(0, user.cloudStorageUsedBytes - reservedBytes)
                }
                reservedBytes = 0
                clip.needsSync = true
                ErrorHandlerService.shared.saveContext(context, caller: "UploadQueue.rollbackReservedStorage")

                throw error
            }

            // Both Storage upload and Firestore write succeeded — now persist local state
            clip.cloudURL = cloudURL
            clip.isUploaded = true
            clip.lastSyncDate = Date()
            reservedBytes = 0 // Quota is now committed, don't release on error
            try context.save()

            // Fetch preferences for post-upload actions
            let uploadPrefs: UserPreferences?
            do {
                uploadPrefs = try context.fetch(FetchDescriptor<UserPreferences>()).first
            } catch {
                uploadLog.error("Failed to fetch UserPreferences for post-upload actions: \(error.localizedDescription)")
                uploadPrefs = nil
            }

            // Auto-delete local file after successful upload if enabled.
            // isAvailableOffline is computed from fileExists, so removing the file
            // automatically makes the clip "cloud-only".
            if uploadPrefs?.autoDeleteAfterUpload == true {
                let localPath = clip.resolvedFilePath
                if FileManager.default.fileExists(atPath: localPath) {
                    do {
                        try FileManager.default.removeItem(atPath: localPath)
                    } catch {
                        uploadLog.error("Failed to auto-delete local file after upload: \(error.localizedDescription)")
                    }
                }
            }

            // Notify user of successful upload if enabled
            if uploadPrefs?.enableUploadNotifications ?? true {
                await PushNotificationService.shared.notifyUploadComplete(thumbnailPath: clip.thumbnailPath)
            }

            // Stop progress monitoring
            progressTask?.cancel()
            progressTask = nil
            activeUploads.removeValue(forKey: upload.clipId)

            // Track upload duration from actual start of this attempt
            let uploadDuration = Date().timeIntervalSince(uploadStartTime)
            AnalyticsService.shared.trackVideoUploaded(
                fileSize: FileManager.default.fileSize(atPath: upload.filePath),
                uploadDuration: uploadDuration
            )

        } catch {
            // Stop progress monitoring on failure
            progressTask?.cancel()
            progressTask = nil
            activeUploads.removeValue(forKey: upload.clipId)

            // Release reserved storage quota on failure
            if reservedBytes > 0 {
                quotaUser?.cloudStorageUsedBytes -= reservedBytes
            }


            // If the clip or athlete was deleted, don't retry — move straight to failed
            if let uploadError = error as? UploadError, case .entityNotFound = uploadError {
                failedUploads.append(upload)
                queueIsDirty = true
                return
            }

            // Handle retry logic
            var updatedUpload = upload
            updatedUpload.lastAttempt = Date()
            updatedUpload.retryCount += 1

            if updatedUpload.retryCount < maxRetries {
                // Schedule retry with exponential backoff
                let delayIndex = min(updatedUpload.retryCount - 1, Self.retryDelays.count - 1)
                let delay = Self.retryDelays[delayIndex]


                let clipId = updatedUpload.clipId
                let retryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    guard let self = self else { return }

                    // Clean up tracking entry
                    self.retryTasks.removeValue(forKey: clipId)

                    // Re-queue only if not cancelled (clearAllQueues cancels these)
                    if !Task.isCancelled {
                        self.pendingUploads.append(updatedUpload)
                        self.pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }
                        self.queueIsDirty = true
                        if !self.isProcessing {
                            self.startProcessing()
                        }
                    }
                }
                retryTasks[clipId] = retryTask
            } else {
                // Max retries reached, move to failed
                failedUploads.append(updatedUpload)
                queueIsDirty = true
            }
        }
    }

    // MARK: - Coach Upload Processing

    /// Processes a coach upload to a shared folder.
    /// Uses VideoCloudManager+SharedFolders for Storage and FirestoreManager for metadata.
    private func processCoachUpload(_ upload: QueuedUpload) async throws {
        guard let folderID = upload.folderID,
              let coachID = upload.coachID,
              let coachName = upload.coachName else {
            throw UploadError.uploadFailed("Missing coach upload metadata")
        }

        // Verify coach still has a valid subscription tier before uploading
        let coachTier = StoreKitManager.shared.currentCoachTier
        if coachTier == .free {
            // Free tier coaches can still upload — no tier gate here.
            // Server-side Firestore rules enforce hasCoachTier() which allows free coaches.
        }

        let localURL = URL(fileURLWithPath: upload.filePath)
        guard FileManager.default.fileExists(atPath: upload.filePath) else {
            throw UploadError.uploadFailed("Local video file not found")
        }

        // Compress video before upload to reduce bandwidth and storage costs.
        // Non-fatal: if compression fails, upload the original file.
        do {
            _ = try await VideoCompressionService.shared.compressForUpload(at: localURL)
        } catch {
            uploadLog.warning("Coach video compression failed, uploading original: \(error.localizedDescription)")
        }

        let cloudManager = VideoCloudManager.shared

        // Upload video to shared folder Storage path with 10-minute timeout
        let downloadURL = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await cloudManager.uploadVideo(
                    localURL: localURL,
                    fileName: upload.fileName,
                    folderID: folderID,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeUploads[upload.clipId] = progress
                        }
                    }
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(600))
                throw UploadError.uploadFailed("Coach upload timed out after 10 minutes")
            }
            guard let result = try await group.next() else {
                throw UploadError.uploadFailed("No upload result received")
            }
            group.cancelAll()
            return result
        }

        // Process video: extract duration + generate/upload thumbnail
        let processed = await CoachVideoProcessingService.shared.process(
            videoURL: localURL,
            fileName: upload.fileName,
            folderID: folderID
        )

        let fileSize = FileManager.default.fileSize(atPath: upload.filePath)

        // Write metadata to Firestore
        do {
            _ = try await FirestoreManager.shared.uploadVideoMetadata(
                fileName: upload.fileName,
                storageURL: downloadURL,
                thumbnail: processed.thumbnailURL.map {
                    ThumbnailMetadata(standardURL: $0, timestamp: 1.0, width: 480, height: 270)
                },
                folderID: folderID,
                uploadedBy: coachID,
                uploadedByName: coachName,
                fileSize: fileSize,
                duration: processed.duration,
                videoType: "instruction",
                uploadedByType: .coach,
                visibility: "private",
                sessionID: upload.sessionID
            )
        } catch {
            // Rollback Storage file on metadata failure
            do {
                try await cloudManager.deleteVideo(fileName: upload.fileName, folderID: folderID)
            } catch {
                uploadLog.error("Failed to rollback Storage file '\(upload.fileName)' after metadata failure: \(error.localizedDescription)")
            }
            throw error
        }

        // Increment session clip count if part of a live session
        if let sessionID = upload.sessionID {
            await CoachSessionManager.shared.incrementClipCount(sessionID: sessionID)
        }

        uploadLog.info("Coach upload completed: \(upload.fileName) → folder \(folderID)")
    }

    // MARK: - Helpers

    /// Generates a deterministic UUID from a string key (e.g., "folderID|fileName").
    /// Used for coach uploads so the same file always gets the same clipId,
    /// enabling reliable duplicate detection across app restarts.
    static func stableUUID(from key: String) -> UUID {
        // Hash the key into two 64-bit values to fill 16 UUID bytes
        var h1: UInt64 = 0
        for char in key.utf8 {
            h1 = h1 &* 31 &+ UInt64(char)
        }
        let h2 = h1 &* 6364136223846793005 &+ 1442695040888963407 // LCG for second half

        // Build UUID bytes directly — no unsafe rebinding needed
        let b1 = UInt8(truncatingIfNeeded: h1 >> 56)
        let b2 = UInt8(truncatingIfNeeded: h1 >> 48)
        let b3 = UInt8(truncatingIfNeeded: h1 >> 40)
        let b4 = UInt8(truncatingIfNeeded: h1 >> 32)
        let b5 = UInt8(truncatingIfNeeded: h1 >> 24)
        let b6 = UInt8(truncatingIfNeeded: h1 >> 16)
        let b7 = UInt8(truncatingIfNeeded: h1 >> 8)
        let b8 = UInt8(truncatingIfNeeded: h1)
        let b9  = UInt8(truncatingIfNeeded: h2 >> 56)
        let b10 = UInt8(truncatingIfNeeded: h2 >> 48)
        let b11 = UInt8(truncatingIfNeeded: h2 >> 40)
        let b12 = UInt8(truncatingIfNeeded: h2 >> 32)
        let b13 = UInt8(truncatingIfNeeded: h2 >> 24)
        let b14 = UInt8(truncatingIfNeeded: h2 >> 16)
        let b15 = UInt8(truncatingIfNeeded: h2 >> 8)
        let b16 = UInt8(truncatingIfNeeded: h2)
        return UUID(uuid: (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16))
    }

    // MARK: - Database Helpers

    private func getModelContext() -> ModelContext? {
        return modelContext
    }

    private func fetchVideoClip(_ id: UUID, context: ModelContext) throws -> VideoClip? {
        let descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate { clip in
                clip.id == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchAthlete(_ id: UUID, context: ModelContext) throws -> Athlete? {
        let descriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { athlete in
                athlete.id == id
            }
        )
        return try context.fetch(descriptor).first
    }
}

// MARK: - Supporting Types

struct QueuedUpload: Identifiable {
    let id = UUID()
    let clipId: UUID
    let athleteId: UUID?       // nil for coach uploads
    let fileName: String
    let filePath: String
    let priority: UploadPriority
    var retryCount: Int
    var lastAttempt: Date?

    // Coach upload fields (nil for athlete uploads)
    let isCoachUpload: Bool
    let folderID: String?
    let coachID: String?
    let coachName: String?
    let sessionID: String?

    var timeUntilRetry: TimeInterval? {
        guard let lastAttempt = lastAttempt, retryCount > 0 else { return nil }
        let delays = UploadQueueManager.retryDelays
        let delayIndex = min(retryCount - 1, delays.count - 1)
        let delay = delays[delayIndex]
        let elapsed = Date().timeIntervalSince(lastAttempt)
        return max(0, delay - elapsed)
    }

    /// Convenience initializer for athlete uploads (backward compatible)
    init(clipId: UUID, athleteId: UUID, fileName: String, filePath: String,
         priority: UploadPriority, retryCount: Int, lastAttempt: Date?) {
        self.clipId = clipId
        self.athleteId = athleteId
        self.fileName = fileName
        self.filePath = filePath
        self.priority = priority
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
        self.isCoachUpload = false
        self.folderID = nil
        self.coachID = nil
        self.coachName = nil
        self.sessionID = nil
    }

    /// Initializer for coach uploads
    init(clipId: UUID, fileName: String, filePath: String, priority: UploadPriority,
         retryCount: Int, lastAttempt: Date?, folderID: String, coachID: String,
         coachName: String, sessionID: String?) {
        self.clipId = clipId
        self.athleteId = nil
        self.fileName = fileName
        self.filePath = filePath
        self.priority = priority
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
        self.isCoachUpload = true
        self.folderID = folderID
        self.coachID = coachID
        self.coachName = coachName
        self.sessionID = sessionID
    }
}

enum UploadPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: UploadPriority, rhs: UploadPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum UploadError: LocalizedError {
    case entityNotFound
    case uploadFailed(String)
    case storageLimitExceeded(usedGB: Double, limitGB: Int)

    var errorDescription: String? {
        switch self {
        case .entityNotFound:
            return "Video clip or athlete not found in database"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .storageLimitExceeded(let usedGB, let limitGB):
            return String(format: "Storage limit reached (%.1f GB of %d GB used). Upgrade your plan for more storage.", usedGB, limitGB)
        }
    }
}

// MARK: - FileManager Extension

extension FileManager {
    func fileSize(atPath path: String) -> Int64 {
        do {
            let attributes = try attributesOfItem(atPath: path)
            return (attributes[.size] as? Int64) ?? 0
        } catch {
            uploadLog.warning("Failed to read file size at '\(path)': \(error.localizedDescription)")
            return 0
        }
    }
}

// MARK: - PendingUpload SwiftData Model

/// Persisted upload queue entry for recovery after app restart
@Model
final class PendingUpload {
    var id: UUID = UUID()
    var clipId: UUID = UUID()
    var athleteId: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var priority: Int = 1
    var retryCount: Int = 0
    var lastAttempt: Date?
    var createdAt: Date = Date()
    var statusRaw: String = "pending"

    // Coach upload fields (added for coach queue integration)
    var isCoachUpload: Bool = false
    var folderID: String?
    var coachID: String?
    var coachName: String?
    var sessionID: String?

    var status: PendingUploadStatus {
        get { PendingUploadStatus(rawValue: statusRaw) ?? PendingUploadStatus.pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        clipId: UUID,
        athleteId: UUID,
        fileName: String,
        filePath: String,
        priority: Int,
        retryCount: Int,
        lastAttempt: Date?,
        status: PendingUploadStatus
    ) {
        self.clipId = clipId
        self.athleteId = athleteId
        self.fileName = fileName
        self.filePath = filePath
        self.priority = priority
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
        self.createdAt = Date()
        self.statusRaw = status.rawValue
    }

    /// Initializer for coach uploads
    init(
        clipId: UUID,
        fileName: String,
        filePath: String,
        priority: Int,
        retryCount: Int,
        lastAttempt: Date?,
        status: PendingUploadStatus,
        folderID: String,
        coachID: String,
        coachName: String,
        sessionID: String?
    ) {
        self.clipId = clipId
        self.athleteId = UUID() // Placeholder for coach uploads
        self.fileName = fileName
        self.filePath = filePath
        self.priority = priority
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
        self.createdAt = Date()
        self.statusRaw = status.rawValue
        self.isCoachUpload = true
        self.folderID = folderID
        self.coachID = coachID
        self.coachName = coachName
        self.sessionID = sessionID
    }
}

enum PendingUploadStatus: String, Codable {
    case pending
    case failed
}
