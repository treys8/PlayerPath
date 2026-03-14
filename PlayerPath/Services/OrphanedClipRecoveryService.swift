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
            #if DEBUG
            print("🔄 OrphanedClipRecovery: No athletes in DB — skipping recovery")
            #endif
            return
        }

        let orphans = findOrphanedVideoFiles(context: context)
        guard !orphans.isEmpty else {
            #if DEBUG
            print("✅ OrphanedClipRecovery: No orphaned video files found")
            #endif
            return
        }

        #if DEBUG
        print("🔄 OrphanedClipRecovery: Found \(orphans.count) orphaned video file(s) — recovering...")
        #endif

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
                #if DEBUG
                print("✅ OrphanedClipRecovery: Recovered \(recoveredCount) clip(s) for \(targetAthlete.name)")
                #endif

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
                    try? context.save()
                }
            } catch {
                #if DEBUG
                print("❌ OrphanedClipRecovery: Failed to save recovered clips: \(error.localizedDescription)")
                #endif
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
            #if DEBUG
            print("❌ OrphanedClipRecovery: Failed to fetch existing clips: \(error.localizedDescription)")
            #endif
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
            #if DEBUG
            print("❌ OrphanedClipRecovery: Failed to scan Clips directory: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Attempts to create a VideoClip record for a single orphaned file.
    /// Returns the clip on success, nil on failure.
    private func recoverClip(at fileURL: URL, athlete: Athlete, context: ModelContext) async -> VideoClip? {
        // Basic file sanity check
        let attributes = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let fileSize = (attributes[.size] as? Int64) ?? 0
        guard fileSize > 10_000 else {
            // Delete tiny/corrupt files so they don't get re-scanned every launch
            #if DEBUG
            print("⚠️ OrphanedClipRecovery: Deleting tiny/corrupt file: \(fileURL.lastPathComponent) (\(fileSize) bytes)")
            #endif
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        // Load duration from the video asset
        let asset = AVURLAsset(url: fileURL)
        let duration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
            guard duration > 0 && duration.isFinite && duration < 3600 else {
                #if DEBUG
                print("⚠️ OrphanedClipRecovery: Invalid duration for \(fileURL.lastPathComponent)")
                #endif
                return nil
            }
        } catch {
            #if DEBUG
            print("⚠️ OrphanedClipRecovery: Could not load asset \(fileURL.lastPathComponent): \(error.localizedDescription)")
            #endif
            return nil
        }

        // Use file system creation date, fall back to now
        let createdAt = (attributes[.creationDate] as? Date) ?? Date()

        // Try to find a pre-existing thumbnail in Documents/Thumbnails
        let thumbnailPath = existingThumbnailPath(for: fileURL)

        // Store a relative path so the clip survives sandbox relocation
        let relativePath = "Clips/\(fileURL.lastPathComponent)"

        // Build the recovered clip — no game, no play result (shows as practice clip)
        let clip = VideoClip(
            fileName: fileURL.lastPathComponent,
            filePath: relativePath
        )
        clip.createdAt = createdAt
        clip.duration = duration
        clip.thumbnailPath = thumbnailPath
        clip.athlete = athlete

        // Link to active season if one exists
        if let activeSeason = athlete.activeSeason {
            clip.season = activeSeason
        }

        context.insert(clip)

        #if DEBUG
        print("🔄 OrphanedClipRecovery: Recovered \(fileURL.lastPathComponent) (\(Int(duration))s)")
        #endif
        return clip
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

        return fileManager.fileExists(atPath: thumbnailURL.path) ? thumbnailURL.path : nil
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
