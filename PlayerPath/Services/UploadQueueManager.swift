//
//  UploadQueueManager.swift
//  PlayerPath
//
//  Manages automatic video upload queue with retry logic and background processing
//

import Foundation
import SwiftData
import Combine

@MainActor
@Observable
final class UploadQueueManager {
    static let shared = UploadQueueManager()

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

    private init() {}

    /// Configure the manager with a ModelContext (call once at app startup)
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupNetworkMonitoring()
        startProcessing()
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

            print("UploadQueueManager: ✅ Successfully uploaded \(upload.fileName)")

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
