//
//  ReelExportOptions.swift
//  PlayerPath
//
//  Transient (non-persisted) knobs for a "social-ready" reel export: an optional
//  baked-in name/caption overlay and an optional vertical 9:16 crop for
//  Instagram/TikTok. There is NO PlayerPath watermark/logo (by product decision).
//
//  `.default` reproduces today's reel byte-for-byte: source aspect, no overlay.
//  Threaded GenerateReelView → ReelStitchCoordinator.generate → VideoStitchingService.stitch.
//
//  Cache key variance: the coordinator suffixes the StitchedReelCache scope string
//  with `cacheSuffix`, which is "" exactly when the reel is visually identical to
//  today's — so default reels still hit the existing cache, and every variant lands
//  in its own file. `contentHash(for:)` and StitchedReelCache are left untouched.
//

import Foundation
import CoreGraphics
import CryptoKit

struct ReelExportOptions: Equatable {
    enum Aspect: Equatable {
        case source          // today's behavior: largest-clip oriented canvas
        case vertical9x16    // 1080×1920 for IG/TikTok
        // .square deferred
    }

    enum CropMode: Equatable {
        case letterbox       // aspect-fit into the canvas (black bars)
        case centerCrop      // aspect-fill the canvas (crops overflow)
    }

    /// Name line (athlete name). nil/blank ⇒ no name drawn.
    var nameText: String?
    /// Secondary caption line (e.g. "vs Tigers · Jun 8"). nil/blank ⇒ no caption drawn.
    var captionText: String?
    var aspect: Aspect = .source
    var cropMode: CropMode = .letterbox

    /// The canonical "today's reel" — used as the seed and as the no-op baseline.
    nonisolated static let `default` = ReelExportOptions()

    // MARK: Resolved (trimmed) text

    var resolvedName: String? {
        let s = (nameText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    var resolvedCaption: String? {
        let s = (captionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    var showsOverlay: Bool { resolvedName != nil || resolvedCaption != nil }

    /// True when the resulting MP4 is pixel-identical to today's default reel, i.e.
    /// source aspect with no overlay (cropMode is irrelevant without a 9:16 crop).
    /// Drives BOTH the stitch codepath branch and `cacheSuffix == ""`, so the two
    /// can never disagree (which would let a variant overwrite the default cache file).
    var isVisuallyDefault: Bool { aspect == .source && !showsOverlay }

    /// Fill (center-crop) only makes sense when we're actually cropping to 9:16.
    var fillCrop: Bool { aspect == .vertical9x16 && cropMode == .centerCrop }

    /// Render canvas for these options. `.source` returns the pipeline's existing
    /// computed canvas (so default output is unchanged); `.vertical9x16` forces 1080×1920.
    func renderSize(sourceCanvas: CGSize) -> CGSize {
        switch aspect {
        case .source:        return sourceCanvas
        case .vertical9x16:  return CGSize(width: 1080, height: 1920)
        }
    }

    /// Filesystem-safe suffix appended to the cache scope key. "" ⟺ `isVisuallyDefault`,
    /// so default reels reuse the existing cache file. Deterministic across launches
    /// (SHA-256, never Swift's per-process `hashValue`).
    var cacheSuffix: String {
        guard !isVisuallyDefault else { return "" }
        var parts: [String] = []
        if aspect == .vertical9x16 {
            parts.append(cropMode == .centerCrop ? "v916fill" : "v916fit")
        }
        if showsOverlay {
            let canonical = "\(resolvedName ?? "")|\(resolvedCaption ?? "")"
            let digest = SHA256.hash(data: Data(canonical.utf8))
            let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
            parts.append("ovl\(hex)")
        }
        return parts.isEmpty ? "" : "-" + parts.joined(separator: "-")
    }
}
