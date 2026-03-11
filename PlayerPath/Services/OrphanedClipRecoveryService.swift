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
            print("🔄 OrphanedClipRecovery: No athletes in DB — skipping recovery")
            return
        }

        let orphans = findOrphanedVideoFiles(context: context)
        guard !orphans.isEmpty else {
            print("✅ OrphanedClipRecovery: No orphaned video files found")
            return
        }

        print("🔄 OrphanedClipRecovery: Found \(orphans.count) orphaned video file(s) — recovering...")

        // Assign to the first athlete found (best guess for single-tester builds;
        // if multiple athletes exist we still pick one rather than lose the footage).
        let targetAthlete = athletes[0]
        var recoveredCount = 0

        for fileURL in orphans {
            if await recoverClip(at: fileURL, athlete: targetAthlete, context: context) {
                recoveredCount += 1
            }
        }

        if recoveredCount > 0 {
            do {
                try context.save()
                print("✅ OrphanedClipRecovery: Recovered \(recoveredCount) clip(s) for \(targetAthlete.name)")
            } catch {
                print("❌ OrphanedClipRecovery: Failed to save recovered clips: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private helpers

    /// Returns video files in Documents/Clips that have no matching VideoClip record.
    private func findOrphanedVideoFiles(context: ModelContext) -> [URL] {
        // Collect all tracked file paths from SwiftData
        let descriptor = FetchDescriptor<VideoClip>()
        let trackedPaths: Set<String>
        do {
            let clips = try context.fetch(descriptor)
            trackedPaths = Set(clips.map { $0.resolvedFilePath })
        } catch {
            print("❌ OrphanedClipRecovery: Failed to fetch existing clips: \(error.localizedDescription)")
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
                !trackedPaths.contains(url.path)
            }
        } catch {
            print("❌ OrphanedClipRecovery: Failed to scan Clips directory: \(error.localizedDescription)")
            return []
        }
    }

    /// Attempts to create a VideoClip record for a single orphaned file.
    private func recoverClip(at fileURL: URL, athlete: Athlete, context: ModelContext) async -> Bool {
        // Basic file sanity check
        let attributes = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let fileSize = (attributes[.size] as? Int64) ?? 0
        guard fileSize > 10_000 else {
            print("⚠️ OrphanedClipRecovery: Skipping tiny/corrupt file: \(fileURL.lastPathComponent)")
            return false
        }

        // Load duration from the video asset
        let asset = AVURLAsset(url: fileURL)
        let duration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
            guard duration > 0 && duration.isFinite && duration < 3600 else {
                print("⚠️ OrphanedClipRecovery: Invalid duration for \(fileURL.lastPathComponent)")
                return false
            }
        } catch {
            print("⚠️ OrphanedClipRecovery: Could not load asset \(fileURL.lastPathComponent): \(error.localizedDescription)")
            return false
        }

        // Use file system creation date, fall back to now
        let createdAt = (attributes[.creationDate] as? Date) ?? Date()

        // Try to find a pre-existing thumbnail in Documents/Thumbnails
        let thumbnailPath = existingThumbnailPath(for: fileURL)

        // Build the recovered clip — no game, no play result (shows as practice clip)
        let clip = VideoClip(
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path
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

        // Generate a thumbnail in the background if none was found
        if thumbnailPath == nil {
            Task {
                let result = await VideoFileManager.generateThumbnail(from: fileURL)
                if case .success(let path) = result {
                    clip.thumbnailPath = path
                    try? context.save()
                }
            }
        }

        print("🔄 OrphanedClipRecovery: Recovered \(fileURL.lastPathComponent) (\(Int(duration))s)")
        return true
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
