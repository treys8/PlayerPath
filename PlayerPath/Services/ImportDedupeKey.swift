//
//  ImportDedupeKey.swift
//  PlayerPath
//
//  Derives and looks up the stable identity of a camera-roll asset brought in by
//  bulk import, so re-picking something already in the library is skipped instead
//  of creating a second copy that charges cloud quota twice.
//

import Foundation
// PhotosPickerItem lives in PhotosUI's SwiftUI overlay — SwiftUI must be
// imported alongside PhotosUI for it to resolve.
import SwiftUI
import SwiftData
import PhotosUI
import CryptoKit

enum ImportDedupeKey {

    /// Bytes hashed from each end of the source. Full-file hashing is not an
    /// option here: the import loop is serial and user-facing, so a multi-GB clip
    /// would stall it for seconds per item. Head+tail+size is enough to separate
    /// distinct camera-roll assets while staying O(1) in file length.
    ///
    /// `nonisolated` because both `contentKey` overloads are, and this module is
    /// MainActor-by-default — an isolated constant would make them unusable from
    /// the detached tasks that do the hashing.
    nonisolated private static let sampleBytes = 256 * 1024

    // MARK: - Derivation

    /// Photos-library asset identity — the preferred key: free, exact, and
    /// immune to re-encoding.
    ///
    /// Non-nil only when the app holds Photos **read** authorization, which
    /// `PhotosReadAccess.requestIfNeeded()` asks for at the bulk-import entry
    /// point. It is still nil when the user declines, so `contentKey` remains a
    /// live path, not a legacy one.
    static func libraryKey(for item: PhotosPickerItem) -> String? {
        guard let id = item.itemIdentifier, !id.isEmpty else { return nil }
        return "pl:\(id)"
    }

    /// Fingerprint of in-memory source bytes — the photo path.
    ///
    /// Hash the SOURCE, never the saved artifact: `PhotoPersistenceService`
    /// re-encodes to JPEG, so a key derived from the stored file would never
    /// match a second import of the same asset.
    ///
    /// `nonisolated` so callers can hop off the main actor; this build is
    /// MainActor-by-default and hashing is pure CPU.
    nonisolated static func contentKey(for data: Data) -> String {
        let head = data.prefix(sampleBytes)
        let tail = data.count > sampleBytes ? data.suffix(sampleBytes) : Data()
        var hasher = SHA256()
        hasher.update(data: head)
        hasher.update(data: tail)
        return "cf:\(data.count):" + hex(hasher.finalize())
    }

    /// Fingerprint of a file already copied to disk — the video path. Safe to
    /// hash the copy because `BulkImportVideoFile` does a byte-for-byte
    /// `copyItem` of what the picker exported.
    ///
    /// Returns nil when the file can't be read; callers must treat that as
    /// "no key" (import it) rather than as a duplicate.
    nonisolated static func contentKey(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let size = Int(try handle.seekToEnd())
            try handle.seek(toOffset: 0)
            let head = try handle.read(upToCount: min(sampleBytes, size)) ?? Data()
            var tail = Data()
            if size > sampleBytes {
                try handle.seek(toOffset: UInt64(max(0, size - sampleBytes)))
                tail = try handle.read(upToCount: sampleBytes) ?? Data()
            }
            var hasher = SHA256()
            hasher.update(data: head)
            hasher.update(data: tail)
            return "cf:\(size):" + hex(hasher.finalize())
        } catch {
            return nil
        }
    }

    /// First 16 bytes of SHA-256 as hex — deterministic across launches (never
    /// Swift's per-process `hashValue`, which would silently stop matching after
    /// every relaunch). Same idiom as `ReelExportOptions.sha4`.
    private nonisolated static func hex(_ digest: SHA256.Digest) -> String {
        digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a claimed-key set contains any content fingerprints.
    ///
    /// Rows imported before the app held read authorization carry `"cf:"` keys,
    /// while new imports carry `"pl:"`. Without checking BOTH, dedupe would miss
    /// across that transition and duplicate everything imported before it. When
    /// this is false — the steady state once a library is all `pl:` — callers can
    /// skip fingerprinting entirely.
    static func containsContentKeys(_ keys: Set<String>) -> Bool {
        keys.contains { $0.hasPrefix("cf:") }
    }

    // MARK: - Lookup

    /// Every dedupe key already claimed by a live photo of this athlete.
    @MainActor
    static func existingPhotoKeys(for athlete: Athlete) -> Set<String> {
        Set((athlete.photos ?? [])
            .lazy
            .filter { !$0.isDeletedRemotely }
            .compactMap(\.importSourceKey))
    }

    /// Every dedupe key already claimed by a live clip of this athlete.
    ///
    /// Walks the relationship rather than issuing a `FetchDescriptor`: a
    /// `#Predicate` over these fields is one careless edit away from a transform
    /// on a model keypath, which traps fatally *inside* fetch and bypasses
    /// do/catch. The relationship is already materialized on every screen that
    /// reaches this code, so the walk costs microseconds.
    @MainActor
    static func existingClipKeys(for athlete: Athlete) -> Set<String> {
        Set((athlete.videoClips ?? [])
            .lazy
            .filter { !$0.isDeletedRemotely }
            .compactMap(\.importSourceKey))
    }
}
