//
//  ReelExportOptions.swift
//  PlayerPath
//
//  Transient (non-persisted) knobs for a "social-ready" reel export: an optional
//  baked-in name/caption overlay, an optional vertical 9:16 crop for Instagram/TikTok,
//  an optional intro title card (prepended segment), and an optional corner
//  "▶ PlayerPath" watermark (defaults ON when customizing; removable — Plus perk).
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
    /// Corner "▶ PlayerPath" mark baked in by ReelOverlayRenderer. Defaults OFF so
    /// `.default` stays byte-identical; the customize sheet seeds it ON.
    var watermarkEnabled: Bool = false
    /// Intro title card, rendered as a prepended segment by ReelCardRenderer.
    var titleCardEnabled: Bool = false
    /// Card hero line (athlete name). nil/blank ⇒ omitted from the card.
    var titleCardTitle: String?
    /// Card event line (e.g. "vs Tigers · Jun 8"). nil/blank ⇒ omitted from the card.
    var titleCardSubtitle: String?

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

    var resolvedCardTitle: String? {
        let s = (titleCardTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    var resolvedCardSubtitle: String? {
        let s = (titleCardSubtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Name/caption text is SET (fields non-blank). See `drawsTextOverlay` for whether
    /// it actually renders.
    var showsTextOverlay: Bool { resolvedName != nil || resolvedCaption != nil }

    /// Whether an intro card segment gets prepended: enabled AND has something to say.
    var needsCardSegment: Bool {
        titleCardEnabled && (resolvedCardTitle != nil || resolvedCardSubtitle != nil)
    }

    /// Name/caption actually drawn over the footage. The title card already announces
    /// both centered, and the overlay layers span the whole timeline (card included) —
    /// drawing them too would show the name twice during the card. So the card
    /// suppresses the footage text; the watermark stays throughout.
    var drawsTextOverlay: Bool { showsTextOverlay && !needsCardSegment }

    /// Whether the stitch must attach the Core Animation tool — either for the
    /// drawn name/caption text or for the corner watermark (which alone still needs it).
    var needsAnimationTool: Bool { drawsTextOverlay || watermarkEnabled }

    /// True when the resulting MP4 is pixel-identical to today's default reel, i.e.
    /// source aspect with nothing drawn — no text overlay, no watermark, no title card
    /// (cropMode is irrelevant without a 9:16 crop). Drives BOTH the stitch codepath
    /// branch and `cacheSuffix == ""`, so the two can never disagree (which would let
    /// a variant overwrite the default cache file).
    var isVisuallyDefault: Bool {
        aspect == .source && !drawsTextOverlay && !watermarkEnabled && !needsCardSegment
    }

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
        // Keyed on what's DRAWN (not what's set): a card suppresses the footage text,
        // so card-on variants with different name/caption text are pixel-identical and
        // should share one cache file.
        if drawsTextOverlay {
            parts.append("ovl" + Self.sha4("\(resolvedName ?? "")|\(resolvedCaption ?? "")"))
        }
        if needsCardSegment {
            parts.append("card" + Self.sha4("\(resolvedCardTitle ?? "")|\(resolvedCardSubtitle ?? "")"))
        }
        if watermarkEnabled {
            parts.append("wm")
        }
        return parts.isEmpty ? "" : "-" + parts.joined(separator: "-")
    }

    /// First 4 bytes of SHA-256 as hex — deterministic across launches (never Swift's
    /// per-process `hashValue`).
    private static func sha4(_ canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
