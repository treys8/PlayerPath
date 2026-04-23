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
}
