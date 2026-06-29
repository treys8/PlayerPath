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

    /// Clips whose capture date matched no existing season and therefore fell
    /// back to the active season — surfaced post-import by BulkVideoImportSheet
    /// so the user can re-home them to a past season. Populated only for
    /// non-pre-pinned imports (no game/practice/seasonOverride).
    private(set) var unmatchedClips: [VideoClip] = []
    private(set) var unmatchedEarliest: Date?
    private(set) var unmatchedLatest: Date?

    private var reservedThisSession: Int64 = 0

    func cancel() {
        isCancelled = true
    }

    func runImport(
        items: [PhotosPickerItem],
        athlete: Athlete,
        modelContext: ModelContext,
        game: Game? = nil,
        practice: Practice? = nil,
        seasonOverride: Season? = nil
    ) async {
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
        unmatchedClips = []
        unmatchedEarliest = nil
        unmatchedLatest = nil

        let tier = SubscriptionGate.effectiveAthleteTier
        let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB

        // Match the canonical creation pattern in ClipPersistenceService:
        // ensure (or create) an active season so imports never land orphaned.
        let activeSeason = SeasonManager.ensureActiveSeason(for: athlete, in: modelContext)
        let allSeasons = athlete.seasons ?? []

        // Fetch user preferences once so we can apply the same auto-upload gate
        // that ClipPersistenceService.saveClip uses (autoUploadToCloud, file size
        // cap, syncHighlightsOnly). Fetched once — preferences don't change mid-import.
        let preferences = (try? modelContext.fetch(FetchDescriptor<UserPreferences>()).first)

        // Stamp the live golf hole onto mid-round imports so they join that
        // hole's auto-highlight reel (built at score-save by ScoreHoleSheet),
        // mirroring ClipPersistenceService.saveClip. Captured once: no scoring
        // happens during an import, so the next-unscored hole is stable across
        // the batch. Nil outside a live golf round (and for non-golf), leaving
        // holeNumber unset exactly as before.
        let liveHole = LiveHoleTracker.shared.currentHole(for: game)
            ?? LiveHoleTracker.shared.currentHole(for: practice)

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

            // When importing into a specific game/practice, prefer that
            // entity's season so the clip lands on the right timeline.
            // Otherwise, an explicit seasonOverride wins over date-matching;
            // fall back to matching by capture date, then the active season.
            let matchedSeason: Season?
            // Tracks the "silent misfile" case: a non-pre-pinned clip whose
            // capture date matched no season and fell back to the active one.
            // Collected after a successful save so the sheet can offer to
            // re-home these to a past season.
            let dateUnmatched: Bool
            if let game = game {
                matchedSeason = game.season ?? activeSeason
                dateUnmatched = false
            } else if let practice = practice {
                matchedSeason = practice.season ?? activeSeason
                dateUnmatched = false
            } else if let seasonOverride {
                matchedSeason = seasonOverride
                dateUnmatched = false
            } else {
                let dateMatch = Season.season(containing: originalDate, in: allSeasons)
                matchedSeason = dateMatch ?? activeSeason
                // Only flag for re-homing when the clip is genuinely OLDER than the
                // current season (predates its start). A clip that matches no season
                // because it's newer-than-any (e.g. a future / clock-skewed capture
                // date) is left on the active season — the "past season" prompt
                // wouldn't apply, and collecting it would seed a future-dated draft.
                if let start = activeSeason?.startDate {
                    dateUnmatched = (dateMatch == nil && originalDate < start)
                } else {
                    dateUnmatched = false
                }
            }

            let clip = VideoClip(
                fileName: stableURL.lastPathComponent,
                filePath: VideoClip.toRelativePath(stableURL.path)
            )
            clip.athlete = athlete
            clip.season = matchedSeason
            clip.seasonName = matchedSeason?.displayName
            clip.thumbnailPath = thumbnailPath
            clip.duration = durationSeconds
            // Photos library creation dates are usually second-precision;
            // bulk imports from the same second tie on `createdAt` and break
            // the list's stable-sort tie-break. Nudge by a microsecond per
            // index — invisible to users, unique within the batch.
            clip.createdAt = originalDate.addingTimeInterval(Double(index) / 1_000_000.0)
            clip.game = game
            clip.practice = practice
            clip.holeNumber = liveHole
            // Denormalize game/practice display fields so data survives cross-device sync
            // even if the relationships can't be re-linked. Matches ClipPersistenceService.
            clip.gameOpponent = game?.opponent
            clip.gameDate = game?.date
            clip.practiceDate = practice?.date
            modelContext.insert(clip)

            do {
                try modelContext.save()

                // Apply auto-upload gate mirroring ClipPersistenceService.saveClip.
                // Skip enqueue when preferences are missing (safer default), when
                // the user disabled auto-upload, when the file exceeds their cap,
                // or when highlights-only sync is on (imported clips are never highlights).
                let fileSizeMB = fileSize / StorageConstants.bytesPerMB
                let shouldEnqueue: Bool = {
                    guard let prefs = preferences else { return false }
                    guard prefs.autoUploadToCloud else { return false }
                    guard fileSizeMB <= prefs.maxVideoFileSize else { return false }
                    guard !prefs.syncHighlightsOnly || clip.isHighlight else { return false }
                    return true
                }()
                if shouldEnqueue {
                    UploadQueueManager.shared.enqueue(clip, athlete: athlete, priority: .normal)
                }

                // Notify dashboard + weekly summary scheduler so they refresh.
                // Matches ClipPersistenceService.saveClip behavior.
                NotificationCenter.default.post(name: .videoRecorded, object: clip)

                succeeded += 1
                reservedThisSession += fileSize

                if dateUnmatched {
                    unmatchedClips.append(clip)
                    unmatchedEarliest = min(unmatchedEarliest ?? originalDate, originalDate)
                    unmatchedLatest = max(unmatchedLatest ?? originalDate, originalDate)
                }
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
