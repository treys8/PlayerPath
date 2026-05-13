//
//  TelestrationConstants.swift
//  PlayerPath
//

import Foundation

enum TelestrationConstants {
    static let maxStrokes = 50
    /// Per-annotation cap on geometric shapes (arrows, lines, circles, rectangles).
    /// Combined with `maxStrokes` gates how much a single drawing can contain,
    /// keeping the stored annotation doc well under Firestore's 1MB limit.
    static let maxShapes = 20

    /// Cadence of the playback time observer used to auto-show drawings as
    /// the video crosses each annotation's timestamp.
    static let timeObserverInterval: Double = 1.0
    /// Lookahead window applied when matching the current playhead against
    /// queued drawings. Must be < `timeObserverInterval` or duplicate fires
    /// become possible.
    static let drawingLookahead: Double = 0.25
    /// Raw PKDrawing byte cap before base64 encoding. Server rule allows ~300KB
    /// base64 (firestore.rules), so this leaves comfortable headroom.
    static let maxDrawingByteSize = 200_000
}
