//
//  BulkVideoImportViewModel.swift
//  PlayerPath
//
//  Drives bulk import of videos from the Photos library. Imports run serially
//  with per-clip quota enforcement so partial success is preserved when the
//  athlete's storage cap is reached mid-batch.
//

import Foundation
import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import os

private let bulkImportLog = Logger(subsystem: "com.playerpath.app", category: "BulkImport")

@MainActor
@Observable
final class BulkVideoImportViewModel {
    enum Status: Equatable {
        case idle
        case importing(current: Int, total: Int)
        case completed(succeeded: Int, failed: Int, stoppedForQuota: Bool, wasCancelled: Bool)
    }

    var status: Status = .idle
    private(set) var isCancelled = false

    private var reservedThisSession: Int64 = 0

    func cancel() {
        isCancelled = true
    }

    func runImport(items: [PhotosPickerItem], athlete: Athlete, modelContext: ModelContext) async {
        let total = items.count
        guard total > 0 else {
            status = .completed(succeeded: 0, failed: 0, stoppedForQuota: false, wasCancelled: false)
            return
        }

        status = .importing(current: 0, total: total)
        var succeeded = 0
        var failed = 0
        var stoppedForQuota = false
        reservedThisSession = 0

        let tier = StoreKitManager.shared.currentTier
        let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB

        // Match the canonical creation pattern in ClipPersistenceService:
        // ensure (or create) an active season so imports never land orphaned.
        let activeSeason = SeasonManager.ensureActiveSeason(for: athlete, in: modelContext)
        let allSeasons = athlete.seasons ?? []

        for (index, item) in items.enumerated() {
            if isCancelled || Task.isCancelled { break }
            status = .importing(current: index + 1, total: total)

            guard let stableURL = await loadAndCopyVideo(item: item) else {
                failed += 1
                continue
            }

            let fileSize = FileManager.default.fileSize(atPath: stableURL.path)

            if let user = athlete.user {
                let projected = user.cloudStorageUsedBytes + reservedThisSession + fileSize
                if projected > limitBytes {
                    try? FileManager.default.removeItem(at: stableURL)
                    stoppedForQuota = true
                    break
                }
            }

            let validation = await VideoFileManager.validateVideo(at: stableURL)
            if case .failure = validation {
                try? FileManager.default.removeItem(at: stableURL)
                failed += 1
                continue
            }

            let thumbnailPath: String?
            switch await VideoFileManager.generateThumbnail(from: stableURL) {
            case .success(let path): thumbnailPath = path
            case .failure: thumbnailPath = nil
            }

            let asset = AVURLAsset(url: stableURL)
            let duration = try? await asset.load(.duration)
            let durationSeconds = duration.map { CMTimeGetSeconds($0) }

            // Prefer the video's embedded capture date (iPhone-shot videos always
            // have this) so old imports don't jam to the top of the Videos tab
            // and don't inflate current-season stats.
            let originalDate: Date = await {
                guard let item = try? await asset.load(.creationDate) else { return Date() }
                return (try? await item.load(.dateValue)) ?? Date()
            }()

            // Match the clip to the season whose date range contains the capture
            // date; fall back to the active season if no existing season covers it.
            let matchedSeason = Self.season(containing: originalDate, in: allSeasons) ?? activeSeason

            let clip = VideoClip(
                fileName: stableURL.lastPathComponent,
                filePath: VideoClip.toRelativePath(stableURL.path)
            )
            clip.athlete = athlete
            clip.season = matchedSeason
            clip.seasonName = matchedSeason?.displayName
            clip.thumbnailPath = thumbnailPath
            clip.duration = durationSeconds
            clip.createdAt = originalDate
            modelContext.insert(clip)

            do {
                try modelContext.save()
                UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .normal)
                succeeded += 1
                reservedThisSession += fileSize
            } catch {
                modelContext.delete(clip)
                VideoFileManager.cleanup(url: stableURL)
                if let thumbPath = thumbnailPath {
                    try? FileManager.default.removeItem(atPath: ThumbnailCache.resolveLocalPath(thumbPath))
                }
                failed += 1
                bulkImportLog.warning("Failed to save imported clip: \(error.localizedDescription)")
            }
        }

        AnalyticsService.shared.trackVideosBulkImported(count: succeeded, totalSizeBytes: reservedThisSession)
        status = .completed(
            succeeded: succeeded,
            failed: failed,
            stoppedForQuota: stoppedForQuota,
            wasCancelled: isCancelled
        )
    }

    /// Finds a season whose start/end date range contains the given date.
    /// Prefers an active match over an archived match when ranges overlap.
    /// Returns nil if no season's range contains the date.
    private static func season(containing date: Date, in seasons: [Season]) -> Season? {
        var bestMatch: Season?
        for season in seasons {
            guard let start = season.startDate, start <= date else { continue }
            let end = season.endDate ?? Date.distantFuture
            guard date <= end else { continue }
            if bestMatch == nil || (season.isActive && bestMatch?.isActive == false) {
                bestMatch = season
            }
        }
        return bestMatch
    }

    private func loadAndCopyVideo(item: PhotosPickerItem) async -> URL? {
        do {
            guard let transferable = try await item.loadTransferable(type: BulkImportVideoFile.self) else {
                return nil
            }
            return transferable.url
        } catch {
            bulkImportLog.warning("loadTransferable failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Transferable that lands picked videos in the same `Clips/` directory the
/// recorder uses, with a UUID filename matching `VideoClip.toRelativePath`'s
/// expectations.
private struct BulkImportVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let clipsDir = documents.appendingPathComponent("Clips", isDirectory: true)
            try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let stableURL = clipsDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: stableURL)
            return BulkImportVideoFile(url: stableURL)
        }
    }
}
