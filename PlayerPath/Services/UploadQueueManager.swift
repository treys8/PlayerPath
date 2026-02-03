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

    private var processingTask: Task<Void, Never>?
    private let maxConcurrentUploads = 2
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [5, 15, 60] // 5s, 15s, 1min

    private var modelContext: ModelContext?
    private var isConfigured = false

    private init() {}

    /// Configure the manager with a ModelContext (call once at app startup)
    func configure(modelContext: ModelContext) {
        guard !isConfigured else {
            print("UploadQueueManager: Already configured, skipping")
            return
        }

        self.modelContext = modelContext
        self.isConfigured = true

        // Restore persisted queue from database
        restoreQueueFromDatabase()

        setupNetworkMonitoring()

        // Start processing if there are pending uploads
        if !pendingUploads.isEmpty {
            print("UploadQueueManager: Restored \(pendingUploads.count) pending uploads from database")
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
                UploadQueueManager.shared.handleBackgroundTask(task as! BGProcessingTask)
            }
        }
        print("UploadQueueManager: Registered background task")
    }

    /// Schedule background upload task
    func scheduleBackgroundUpload() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("UploadQueueManager: Scheduled background upload task")
        } catch {
            print("UploadQueueManager: Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Handle background task execution
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        print("UploadQueueManager: Background task started")

        // Schedule next background task
        scheduleBackgroundUpload()

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.processingTask?.cancel()
                self?.persistQueueToDatabase()
                print("UploadQueueManager: Background task expired, queue persisted")
            }
        }

        // Process uploads
        Task { @MainActor in
            // Process a limited batch in background
            await processBackgroundBatch()

            // Persist state and complete
            persistQueueToDatabase()
            task.setTaskCompleted(success: true)
            print("UploadQueueManager: Background task completed")
        }
    }

    /// Process a limited batch of uploads for background execution
    private func processBackgroundBatch() async {
        guard let modelContext = modelContext else { return }

        // Process up to 3 uploads in background
        let maxBackgroundUploads = 3
        var processed = 0

        while processed < maxBackgroundUploads && !pendingUploads.isEmpty {
            guard let upload = pendingUploads.first else { break }
            await processUpload(upload, context: modelContext)
            processed += 1
        }
    }

    private func setupNetworkMonitoring() {
        // Listen for network status changes
        NotificationCenter.default.addObserver(
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

        // Listen for app going to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Persist queue and schedule background task
                self.persistQueueToDatabase()
                if !self.pendingUploads.isEmpty {
                    self.scheduleBackgroundUpload()
                }
            }
        }

        // Listen for app becoming active
        NotificationCenter.default.addObserver(
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
    }

    // MARK: - Queue Persistence

    /// Persist pending uploads to database for recovery after app restart
    func persistQueueToDatabase() {
        guard let modelContext = modelContext else {
            print("UploadQueueManager: Cannot persist - no ModelContext")
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

            // Insert current pending uploads
            for upload in pendingUploads {
                let persistedUpload = PendingUpload(
                    clipId: upload.clipId,
                    athleteId: upload.athleteId,
                    fileName: upload.fileName,
                    filePath: upload.filePath,
                    priority: upload.priority.rawValue,
                    retryCount: upload.retryCount,
                    lastAttempt: upload.lastAttempt,
                    status: PendingUploadStatus.pending
                )
                modelContext.insert(persistedUpload)
            }

            // Also persist failed uploads
            for upload in failedUploads {
                let persistedUpload = PendingUpload(
                    clipId: upload.clipId,
                    athleteId: upload.athleteId,
                    fileName: upload.fileName,
                    filePath: upload.filePath,
                    priority: upload.priority.rawValue,
                    retryCount: upload.retryCount,
                    lastAttempt: upload.lastAttempt,
                    status: PendingUploadStatus.failed
                )
                modelContext.insert(persistedUpload)
            }

            try modelContext.save()
            print("UploadQueueManager: Persisted \(pendingUploads.count) pending + \(failedUploads.count) failed uploads")
        } catch {
            print("UploadQueueManager: Failed to persist queue: \(error.localizedDescription)")
        }
    }

    /// Restore pending uploads from database on app launch
    private func restoreQueueFromDatabase() {
        guard let modelContext = modelContext else {
            print("UploadQueueManager: Cannot restore - no ModelContext")
            return
        }

        do {
            let descriptor = FetchDescriptor<PendingUpload>(
                sortBy: [SortDescriptor(\PendingUpload.createdAt, order: .forward)]
            )
            let persistedUploads = try modelContext.fetch(descriptor)

            // Restore to in-memory queues
            for persisted in persistedUploads {
                // Verify the video clip still exists
                let clipIdToFind = persisted.clipId
                let clipDescriptor = FetchDescriptor<VideoClip>(
                    predicate: #Predicate<VideoClip> { clip in
                        clip.id == clipIdToFind
                    }
                )
                guard let clip = try modelContext.fetch(clipDescriptor).first else {
                    // Clip no longer exists, delete persisted record
                    modelContext.delete(persisted)
                    continue
                }

                // Skip if already uploaded
                if clip.isUploaded {
                    modelContext.delete(persisted)
                    continue
                }

                let queuedUpload = QueuedUpload(
                    clipId: persisted.clipId,
                    athleteId: persisted.athleteId,
                    fileName: persisted.fileName,
                    filePath: persisted.filePath,
                    priority: UploadPriority(rawValue: persisted.priority) ?? .normal,
                    retryCount: persisted.retryCount,
                    lastAttempt: persisted.lastAttempt
                )

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
            print("UploadQueueManager: Restored \(pendingUploads.count) pending + \(failedUploads.count) failed uploads")
        } catch {
            print("UploadQueueManager: Failed to restore queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    /// Queues a video for upload
    func enqueue(_ clip: VideoClip, athlete: Athlete, priority: UploadPriority = .normal) {
        // Don't queue if already uploaded
        guard !clip.isUploaded else {
            print("UploadQueueManager: Clip already uploaded, skipping: \(clip.fileName)")
            return
        }

        // Don't queue if already in queue
        guard !pendingUploads.contains(where: { $0.clipId == clip.id }) else {
            print("UploadQueueManager: Clip already queued: \(clip.fileName)")
            return
        }

        let upload = QueuedUpload(
            clipId: clip.id,
            athleteId: athlete.id,
            fileName: clip.fileName,
            filePath: clip.filePath,
            priority: priority,
            retryCount: 0,
            lastAttempt: nil
        )

        pendingUploads.append(upload)
        pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }

        print("UploadQueueManager: Queued upload for \(clip.fileName) (priority: \(priority))")

        // Trigger processing if not already running
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

        print("UploadQueueManager: Manually retrying upload for \(upload.fileName)")
    }

    /// Cancels a pending upload
    func cancel(_ clipId: UUID) {
        pendingUploads.removeAll { $0.clipId == clipId }
        activeUploads.removeValue(forKey: clipId)
        print("UploadQueueManager: Cancelled upload for clip \(clipId)")
    }

    /// Clears all upload queues - call on logout or account switch
    func clearAllQueues() {
        // Stop any active processing
        processingTask?.cancel()
        processingTask = nil

        // Clear in-memory queues
        pendingUploads.removeAll()
        failedUploads.removeAll()
        activeUploads.removeAll()
        isProcessing = false

        // Clear persisted records from database
        guard let modelContext = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<PendingUpload>()
            let persistedUploads = try modelContext.fetch(descriptor)

            for upload in persistedUploads {
                modelContext.delete(upload)
            }

            try modelContext.save()
            print("UploadQueueManager: Cleared all upload queues")
        } catch {
            print("UploadQueueManager: Failed to clear persisted uploads: \(error)")
        }
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
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }

            print("UploadQueueManager: Processing complete, queue empty")
        }
    }

    private func processNextBatch() async {
        guard let modelContext = await getModelContext() else {
            print("UploadQueueManager: Cannot process without ModelContext")
            return
        }

        // Check network conditions
        let networkMonitor = ConnectivityMonitor.shared
        let descriptor = FetchDescriptor<UserPreferences>()
        let preferences = try? modelContext.fetch(descriptor).first

        guard networkMonitor.shouldAllowUploads(preferences: preferences) else {
            if !networkMonitor.isConnected {
                print("UploadQueueManager: Pausing uploads - no internet connection")
            } else if networkMonitor.connectionType == .cellular && !(preferences?.allowCellularUploads ?? false) {
                print("UploadQueueManager: Pausing uploads - cellular uploads disabled")
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

        // Mark as active
        activeUploads[upload.clipId] = 0.0

        print("UploadQueueManager: Processing upload for \(upload.fileName) (attempt \(upload.retryCount + 1))")

        do {
            // Fetch VideoClip and Athlete from database
            guard let clip = try fetchVideoClip(upload.clipId, context: context),
                  let athlete = try fetchAthlete(upload.athleteId, context: context) else {
                throw UploadError.entityNotFound
            }

            // Perform upload with progress updates
            let cloudManager = VideoCloudManager.shared
            let cloudURL = try await cloudManager.uploadVideo(clip, athlete: athlete)

            // Monitor progress
            let progressTask = Task { @MainActor in
                while activeUploads[upload.clipId] != nil {
                    if let progress = cloudManager.uploadProgress[upload.clipId] {
                        activeUploads[upload.clipId] = progress
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }

            // Update clip with cloud URL
            clip.cloudURL = cloudURL
            clip.isUploaded = true
            clip.lastSyncDate = Date()
            try context.save()

            // Stop progress monitoring
            progressTask.cancel()
            activeUploads.removeValue(forKey: upload.clipId)

            // Save metadata to Firestore for cross-device sync
            do {
                try await cloudManager.saveVideoMetadataToFirestore(clip, athlete: athlete, downloadURL: cloudURL)
                print("UploadQueueManager: ✅ Successfully uploaded and synced \(upload.fileName)")
            } catch {
                // Log but don't fail - local upload succeeded
                print("UploadQueueManager: ⚠️ Upload succeeded but Firestore sync failed: \(error.localizedDescription)")
            }

            // Track analytics (estimate upload duration from last attempt)
            let uploadDuration = upload.lastAttempt.map { Date().timeIntervalSince($0) } ?? 0
            AnalyticsService.shared.trackVideoUploaded(
                fileSize: FileManager.default.fileSize(atPath: upload.filePath),
                uploadDuration: uploadDuration
            )

        } catch {
            activeUploads.removeValue(forKey: upload.clipId)

            print("UploadQueueManager: ❌ Upload failed for \(upload.fileName): \(error.localizedDescription)")

            // Handle retry logic
            var updatedUpload = upload
            updatedUpload.lastAttempt = Date()
            updatedUpload.retryCount += 1

            if updatedUpload.retryCount < maxRetries {
                // Schedule retry with exponential backoff
                let delayIndex = min(updatedUpload.retryCount - 1, retryDelays.count - 1)
                let delay = retryDelays[delayIndex]

                print("UploadQueueManager: Scheduling retry in \(Int(delay))s (attempt \(updatedUpload.retryCount + 1)/\(maxRetries))")

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    // Re-queue if not cancelled
                    if !Task.isCancelled {
                        self.pendingUploads.append(updatedUpload)
                        self.pendingUploads.sort { $0.priority.rawValue > $1.priority.rawValue }
                    }
                }
            } else {
                // Max retries reached, move to failed
                failedUploads.append(updatedUpload)
                print("UploadQueueManager: Max retries reached for \(upload.fileName), moving to failed queue")
            }
        }
    }

    // MARK: - Database Helpers

    private func getModelContext() async -> ModelContext? {
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
    let athleteId: UUID
    let fileName: String
    let filePath: String
    let priority: UploadPriority
    var retryCount: Int
    var lastAttempt: Date?

    var timeUntilRetry: TimeInterval? {
        guard let lastAttempt = lastAttempt else { return nil }
        let delays: [TimeInterval] = [5, 15, 60]
        let delayIndex = min(retryCount - 1, delays.count - 1)
        let delay = delays[delayIndex]
        let elapsed = Date().timeIntervalSince(lastAttempt)
        return max(0, delay - elapsed)
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

    var errorDescription: String? {
        switch self {
        case .entityNotFound:
            return "Video clip or athlete not found in database"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        }
    }
}

// MARK: - FileManager Extension

extension FileManager {
    func fileSize(atPath path: String) -> Int64 {
        guard let attributes = try? attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
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
}

enum PendingUploadStatus: String, Codable {
    case pending
    case failed
}
