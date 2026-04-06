//
//  OrphanedClipRecoveryService.swift
//  PlayerPath
//
//  Scans Documents/Clips for video files that exist on disk but have no
//  corresponding SwiftData record — which happens when a SwiftData store is
//  destroyed between TestFlight builds due to schema changes. Recovered clips
//  appear as untagged practice videos so testers don't permanently lose footage.
//

import Foundation
import SwiftData
import os

private let recoveryLog = Logger(subsystem: "com.playerpath.app", category: "OrphanedClipRecovery")
import AVFoundation

@MainActor
final class OrphanedClipRecoveryService {

    static let shared = OrphanedClipRecoveryService()
    private init() {}

    private let fileManager = FileManager.default

    // MARK: - Public entry point

    /// Call once after the model context and current athlete are available.
    /// Safe to call on every launch — it's fully idempotent.
    func recoverIfNeeded(context: ModelContext, athletes: [Athlete]) async {
        guard !athletes.isEmpty else {
            recoveryLog.debug("No athletes in DB — skipping recovery")
            return
        }

        let orphans = findOrphanedVideoFiles(context: context)
        guard !orphans.isEmpty else {
            recoveryLog.debug("No orphaned video files found")
            return
        }

        recoveryLog.info("Found \(orphans.count) orphaned video file(s) — recovering...")

        // Pick the most recently created athlete as the best guess for ownership.
        // For single-athlete accounts this is the only one; for multi-athlete it's
        // the most likely active player. Sorted descending by createdAt.
        let sortedAthletes = athletes.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        guard let targetAthlete = sortedAthletes.first else { return }
        var recoveredCount = 0
        var clipsNeedingThumbnails: [(VideoClip, URL)] = []

        for fileURL in orphans {
            if let clip = await recoverClip(at: fileURL, athlete: targetAthlete, context: context) {
                recoveredCount += 1
                if clip.thumbnailPath == nil {
                    clipsNeedingThumbnails.append((clip, fileURL))
                }
            }
        }

        if recoveredCount > 0 {
            do {
                try context.save()
                recoveryLog.info("Recovered \(recoveredCount) clip(s) for \(targetAthlete.name, privacy: .private)")

                // Generate thumbnails AFTER the bulk save succeeds, so we never
                // commit a clip that the main flow considered failed.
                for (clip, fileURL) in clipsNeedingThumbnails {
                    let result = await VideoFileManager.generateThumbnail(from: fileURL)
                    if case .success(let path) = result {
                        clip.thumbnailPath = path
                    }
                }
                // Single save for all thumbnails
                if !clipsNeedingThumbnails.isEmpty {
                    ErrorHandlerService.shared.saveContext(context, caller: "OrphanedClipRecovery.saveThumbnails")
                }
            } catch {
                recoveryLog.error("Failed to save recovered clips: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private helpers

    /// Returns video files in Documents/Clips that have no matching VideoClip record.
    private func findOrphanedVideoFiles(context: ModelContext) -> [URL] {
        // Collect only file names from SwiftData to avoid loading full model objects.
        // All orphan candidates are in Documents/Clips, so comparing by fileName is sufficient.
        let descriptor = FetchDescriptor<VideoClip>()
        let trackedFileNames: Set<String>
        do {
            let clips = try context.fetch(descriptor)
            trackedFileNames = Set(clips.map { $0.fileName })
        } catch {
            recoveryLog.error("Failed to fetch existing clips: \(error.localizedDescription)")
            return []
        }

        // Locate Documents/Clips directory
        guard let clipsURL = clipsDirectoryURL() else { return [] }
        guard fileManager.fileExists(atPath: clipsURL.path) else { return [] }

        // Find all video files not already tracked
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: clipsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return contents.filter { url in
                videoExtensions.contains(url.pathExtension.lowercased()) &&
                !trackedFileNames.contains(url.lastPathComponent)
            }
        } catch {
            recoveryLog.error("Failed to scan Clips directory: \(error.localizedDescription)")
            return []
        }
    }

    /// Attempts to create a VideoClip record for a single orphaned file.
    /// Returns the clip on success, nil on failure.
    private func recoverClip(at fileURL: URL, athlete: Athlete, context: ModelContext) async -> VideoClip? {
        // Basic file sanity check
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch {
            recoveryLog.warning("Cannot read attributes for orphaned file '\(fileURL.lastPathComponent, privacy: .private)': \(error.localizedDescription)")
            return nil
        }
        let fileSize = (attributes[.size] as? Int64) ?? 0
        guard fileSize > 10_000 else {
            // Delete tiny/corrupt files so they don't get re-scanned every launch
            recoveryLog.warning("Deleting tiny/corrupt file: \(fileURL.lastPathComponent, privacy: .private) (\(fileSize) bytes)")
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                recoveryLog.warning("Failed to delete tiny/corrupt file '\(fileURL.lastPathComponent, privacy: .private)': \(error.localizedDescription)")
            }
            return nil
        }

        // Load duration from the video asset
        let asset = AVURLAsset(url: fileURL)
        let duration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
            guard duration > 0 && duration.isFinite && duration < 3600 else {
                recoveryLog.warning("Invalid duration for \(fileURL.lastPathComponent, privacy: .private)")
                return nil
            }
        } catch {
            recoveryLog.warning("Could not load asset \(fileURL.lastPathComponent, privacy: .private): \(error.localizedDescription)")
            return nil
        }

        // Use file system creation date, fall back to now
        let createdAt = (attributes[.creationDate] as? Date) ?? Date()

        // Try to find a pre-existing thumbnail in Documents/Thumbnails
        let thumbnailPath = existingThumbnailPath(for: fileURL)

        // Store a relative path so the clip survives sandbox relocation
        let relativePath = "Clips/\(fileURL.lastPathComponent)"

        // Build the recovered clip
        let clip = VideoClip(
            fileName: fileURL.lastPathComponent,
            filePath: relativePath
        )
        clip.createdAt = createdAt
        clip.duration = duration
        clip.thumbnailPath = thumbnailPath
        clip.athlete = athlete

        // Attempt to match the clip to a game based on the file's creation date
        if let matchedGame = findMatchingGame(for: athlete, fileDate: createdAt) {
            clip.game = matchedGame
            clip.gameOpponent = matchedGame.opponent
            clip.gameDate = matchedGame.date
            if let season = matchedGame.season {
                clip.season = season
                clip.seasonName = season.displayName
            }
            recoveryLog.info("Matched \(fileURL.lastPathComponent, privacy: .private) to game vs \(matchedGame.opponent)")
        } else if let activeSeason = athlete.activeSeason {
            // No game match — link to active season as a practice clip
            clip.season = activeSeason
        }

        context.insert(clip)

        recoveryLog.debug("Recovered \(fileURL.lastPathComponent, privacy: .private) (\(Int(duration))s)")
        return clip
    }

    /// Finds the best matching game for an athlete on the same calendar day as the file date.
    /// If multiple games exist on the same day, returns the one whose scheduled time is closest.
    private func findMatchingGame(for athlete: Athlete, fileDate: Date) -> Game? {
        let calendar = Calendar.current
        let games = (athlete.games ?? []).filter { game in
            guard let gameDate = game.date else { return false }
            return calendar.isDate(gameDate, inSameDayAs: fileDate)
        }

        guard !games.isEmpty else { return nil }

        // Single match — return it directly
        if games.count == 1 { return games.first }

        // Multiple games on the same day — pick the one closest in time
        return games.min(by: { a, b in
            let distA = abs((a.date ?? .distantPast).timeIntervalSince(fileDate))
            let distB = abs((b.date ?? .distantPast).timeIntervalSince(fileDate))
            return distA < distB
        })
    }

    /// Returns an existing thumbnail path for the given video file URL, if one is present.
    private func existingThumbnailPath(for videoURL: URL) -> String? {
        guard let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let thumbnailURL = documentsURL
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent("\(baseName)_thumb.jpg")

        guard fileManager.fileExists(atPath: thumbnailURL.path) else { return nil }
        // Store relative so the path survives sandbox relocation.
        return VideoClip.toRelativePath(thumbnailURL.path)
    }

    private func clipsDirectoryURL() -> URL? {
        guard let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        return documentsURL.appendingPathComponent("Clips", isDirectory: true)
    }
}
