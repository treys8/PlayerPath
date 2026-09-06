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
        case completed(BulkImportOutcome)
    }

    var status: Status = .idle
    private(set) var isCancelled = false

    /// Duplicates skipped so far in the running batch.
    ///
    /// Surfaced live because recognizing a duplicate video requires exporting it
    /// from the Photos library first — `PhotosPickerItem.itemIdentifier` is nil
    /// without Photos READ authorization, which this app never requests (every
    /// call site asks for `.addOnly`). So a re-pick of an already-imported batch
    /// does the full export work and then discards it. Showing this count climb
    /// is what makes that time legible instead of looking like a stall.
    private(set) var skippedSoFar = 0

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
        seasonOverride: Season? = nil,
        wasResume: Bool = false
    ) async {
        let total = items.count
        var outcome = BulkImportOutcome()
        outcome.wasResume = wasResume
        guard total > 0 else {
            status = .completed(outcome)
            return
        }

        status = .importing(current: 0, total: total)
        // Reset with the rest of the per-run state: a view model that ever runs a
        // second import would otherwise start already-cancelled.
        isCancelled = false
        reservedThisSession = 0
        skippedSoFar = 0
        unmatchedClips = []
        unmatchedEarliest = nil
        unmatchedLatest = nil

        // Dedupe keys already claimed by this athlete's live clips, read once.
        // `insert(_:).inserted` below makes the set do double duty: it also
        // catches the same asset appearing twice within this one batch.
        var claimed = ImportDedupeKey.existingClipKeys(for: athlete)
        // Only fingerprint when some existing row actually needs it — see
        // `containsContentKeys`. Once a library is all library-identifier keys
        // this stays false and the hash is skipped entirely.
        let mustCheckContentKeys = ImportDedupeKey.containsContentKeys(claimed)

        // One storage snapshot for the whole batch — it stats every un-uploaded
        // file in the library, so it must not run per item. Counts bytes already
        // committed to disk but not yet uploaded: `cloudStorageUsedBytes` alone
        // under-reports by the entire local backlog when auto-upload is off,
        // which lets an import commit media that can never be backed up.
        let user = athlete.user
        var storage: ProjectedCloudStorage.Snapshot?
        if let user {
            storage = await ProjectedCloudStorage.snapshot(for: user)
        }

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

            // FIRST: the free check. With Photos read access the library
            // identifier is known before any bytes move, so a re-pick costs
            // nothing — no export, no transcode, no temp file. This is the whole
            // reason `PhotosReadAccess` asks for read authorization.
            let libraryKey = ImportDedupeKey.libraryKey(for: item)
            if let libraryKey, claimed.contains(libraryKey) {
                outcome.skippedDuplicates += 1
                skippedSoFar = outcome.skippedDuplicates
                continue
            }

            guard let stableURL = await loadAndCopyVideo(item: item) else {
                // Tracked apart from `failed`: an all-load-failure run means the
                // picker selection went stale (see BulkImportOutcome.remaining),
                // not that the media is bad.
                outcome.loadFailures += 1
                continue
            }

            // SECOND: the fingerprint, needed when there is no library key (access
            // declined) or when older rows still carry `cf:` keys. Safe to hash the
            // copy rather than the source: `BulkImportVideoFile` does a byte-for-byte
            // `copyItem` of what the picker exported, so these are those bytes.
            var contentKey: String?
            if libraryKey == nil || mustCheckContentKeys {
                let path = stableURL.path
                contentKey = await Task.detached(priority: .userInitiated) {
                    ImportDedupeKey.contentKey(atPath: path)
                }.value
            }
            // Prefer the library identifier when storing: it survives re-encoding,
            // which a fingerprint of a `.compatible` HEVC export may not.
            let dedupeKey = libraryKey ?? contentKey

            // Test membership now, but CLAIM only after the row is safely saved.
            // Claiming here would mark an asset as present even if it then failed
            // validation or its save threw, so a genuine retry later in the same
            // batch would be reported as "already in your library" with nothing
            // actually written.
            if let contentKey, claimed.contains(contentKey) {
                VideoFileManager.cleanup(url: stableURL)
                outcome.skippedDuplicates += 1
                skippedSoFar = outcome.skippedDuplicates
                continue
            }

            let fileSize = FileManager.default.fileSize(atPath: stableURL.path)

            if let storage, !storage.fits(fileSize, alreadyReserved: reservedThisSession) {
                VideoFileManager.cleanup(url: stableURL)
                outcome.stoppedForQuota = true
                // Always a real number, even when nothing succeeded, so the
                // upgrade sheet can quote a certain figure instead of an estimate.
                outcome.blockedItemBytes = fileSize
                // Inclusive of the current item — it did not land.
                outcome.remaining = Array(items[index...])
                break
            }

            let validation = await VideoFileManager.validateVideo(at: stableURL)
            if case .failure = validation {
                try? FileManager.default.removeItem(at: stableURL)
                outcome.failed += 1
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
            // Set before insert, with no await in between, so the row can never
            // exist without the key that keeps a re-pick from duplicating it.
            clip.importSourceKey = dedupeKey
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

                outcome.succeeded += 1
                if let dedupeKey { claimed.insert(dedupeKey) }
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
                outcome.failed += 1
                bulkImportLog.warning("Failed to save imported clip: \(error.localizedDescription)")
            }
        }

        outcome.importedBytes = reservedThisSession
        outcome.wasCancelled = isCancelled
        outcome.resumeSeason = seasonOverride
        // Carried so the storage-full sheet can quote real figures without taking
        // a second snapshot — and, more importantly, without an await between the
        // import ending and the sheet appearing, during which the screen is live.
        outcome.storageSnapshot = storage

        AnalyticsService.shared.trackVideosBulkImported(
            count: outcome.succeeded,
            skippedDuplicates: outcome.skippedDuplicates,
            stoppedForQuota: outcome.stoppedForQuota,
            wasResume: wasResume,
            totalSizeBytes: outcome.importedBytes
        )
        status = .completed(outcome)
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
