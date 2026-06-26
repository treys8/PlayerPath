//
//  ReelStitchCoordinator.swift
//  PlayerPath
//
//  Drives on-demand stitching of a highlight reel: cache lookup → VideoStitchingService
//  → ready URL, with a small idle/generating/ready/failed state machine. One instance
//  backs each generation surface (GenerateReelView). Mirrors the proven inline flow in
//  TodaysReelHeroCard.generate() but is reusable across game / season / golf reels.
//
//  Stitching needs LOCAL files — VideoStitchingService filters on fileExists, so
//  cloud-only clips are dropped here up front and surfaced via usableCount/requestedCount
//  ("Built from N of M clips").
//

import Foundation
import os

nonisolated private let coordinatorLog = Logger(subsystem: "com.playerpath.app", category: "ReelStitch")

@MainActor
@Observable
final class ReelStitchCoordinator {
    enum State: Equatable {
        case idle
        case generating(progress: Float)
        case ready(URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Clips requested vs. clips actually usable (local file present). When
    /// `usableCount < requestedCount` the surface shows a "built from N of M" note.
    private(set) var requestedCount = 0
    private(set) var usableCount = 0

    private var task: Task<Void, Never>?

    /// Cache-first stitch of `clips` (in the given order) under `scopeKey`, optionally
    /// applying social-export `options` (9:16 crop and/or name/caption overlay).
    /// No-op if already generating. Resolves to `.failed` with friendly copy when
    /// no clip is available locally yet.
    ///
    /// `options.cacheSuffix` is appended to `scopeKey` so each variant caches to its
    /// own file; for `.default` the suffix is "" and the key is unchanged — default
    /// reels keep hitting the existing cache and re-render nothing.
    func generate(clips: [VideoClip], scopeKey: String, options: ReelExportOptions = .default) {
        if case .generating = state { return }

        // Drop cloud-only clips — the stitcher can't read them. Preserve order.
        let localClips = clips.filter { FileManager.default.fileExists(atPath: $0.resolvedFilePath) }
        requestedCount = clips.count
        usableCount = localClips.count

        guard !localClips.isEmpty else {
            state = .failed("These clips aren't downloaded to this device yet. Try again once they finish syncing.")
            return
        }

        let effectiveScope = scopeKey + options.cacheSuffix

        // Cache hit — same scope + options + clip set already stitched.
        if let cached = StitchedReelCache.cachedURLIfPresent(scopeKey: effectiveScope, clips: localClips) {
            state = .ready(cached)
            return
        }

        let outputURL = StitchedReelCache.url(scopeKey: effectiveScope, clips: localClips)
        let sourceURLs = localClips.map { $0.resolvedFileURL }

        state = .generating(progress: 0)
        task = Task { @MainActor in
            do {
                let url = try await VideoStitchingService.stitch(
                    sourceURLs: sourceURLs,
                    outputURL: outputURL,
                    options: options
                ) { [weak self] p in
                    guard let self else { return }
                    if case .generating = self.state { self.state = .generating(progress: p) }
                }
                guard !Task.isCancelled else { return }
                // Guard a vanished/empty output before handing a URL to share/save.
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                guard fileSize > 0 else {
                    // Delete the empty file — the cache keys on existence only, so leaving
                    // it would make every Retry serve the same zero-byte "hit" forever.
                    try? FileManager.default.removeItem(at: url)
                    coordinatorLog.error("Reel stitch produced no usable file at \(url.lastPathComponent)")
                    state = .failed("The reel couldn't be exported. Please try again.")
                    return
                }
                state = .ready(url)
                Haptics.success()
            } catch {
                // A cancel (view dismissed mid-stitch) surfaces as either
                // CancellationError or VideoStitchingService's StitchError.cancelled —
                // treat both as a quiet return to idle, not a user-facing failure.
                if Task.isCancelled || error is CancellationError {
                    if case .generating = state { state = .idle }
                    return
                }
                coordinatorLog.error("Reel stitch failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Cancels any in-flight stitch. Call on view disappear.
    func cancel() {
        task?.cancel()
        task = nil
        if case .generating = state { state = .idle }
    }
}
