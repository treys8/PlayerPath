//
//  StitchedReelCache.swift
//  PlayerPath
//
//  On-disk cache for stitched highlight-reel MP4s. Generalized from the old
//  date-only "TodaysReelCache": a reel is keyed by an arbitrary scope string
//  ("today_<athleteID>", "game_<gameID>", "season_<seasonID>", "reel_<reelID>")
//  plus a content hash of the exact clip set it was built from.
//
//  Putting the content hash IN THE FILENAME makes freshness trivial and correct:
//  any add/remove/reorder — or a re-recorded clip whose createdAt changes —
//  yields a different filename, so a stale reel can never be reused after its
//  source set changes (the old mtime-vs-createdAt check could not detect a
//  *removed* clip). The orphaned file ages out via cleanupOlderThan(days:).
//

import Foundation
import CryptoKit

/// All members are `nonisolated` — the cache touches only FileManager + CryptoKit,
/// all thread-safe. Lives in a SwiftUI file that can default to main-actor isolation.
nonisolated enum StitchedReelCache {
    private static let folderName = "stitched_reels"

    private static var folderURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Stable 16-hex-char fingerprint of the ordered clip set. Deterministic across
    /// launches (SHA-256 over a canonical string), unlike Swift's per-process-seeded
    /// `Hasher`, which would never produce a cache hit on a later launch.
    static func contentHash(for clips: [VideoClip]) -> String {
        let canonical = clips
            .map { "\($0.id.uuidString):\(Int(($0.createdAt ?? .distantPast).timeIntervalSince1970))" }
            .joined(separator: ",")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Destination URL for a reel of `clips` under `scopeKey`. Same scope + same
    /// clip set always maps to the same path (cache hit); any change maps elsewhere.
    static func url(scopeKey: String, clips: [VideoClip]) -> URL {
        let folder = folderURL ?? FileManager.default.temporaryDirectory
        let safeScope = scopeKey.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent("\(safeScope)_\(contentHash(for: clips)).mp4")
    }

    /// The cached reel URL if a file for this exact (scope, clip set) already
    /// exists on disk; otherwise nil (caller should stitch).
    static func cachedURLIfPresent(scopeKey: String, clips: [VideoClip]) -> URL? {
        let candidate = url(scopeKey: scopeKey, clips: clips)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Removes cached reels whose modification date is older than `days` days ago.
    /// Safe to call from a detached background task (see AppDelegate launch).
    static func cleanupOlderThan(days: Int) {
        removeLegacyDailyReelsFolder()
        guard let folder = folderURL else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate,
                  mtime < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// One-time cleanup of the pre-rename "daily_reels" cache folder so upgraded
    /// installs don't leak the old date-named today-reel MP4s indefinitely.
    /// No-op once the folder is gone.
    private static func removeLegacyDailyReelsFolder() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let legacy = caches.appendingPathComponent("daily_reels", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }
}
