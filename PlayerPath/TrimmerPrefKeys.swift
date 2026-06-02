//
//  TrimmerPrefKeys.swift
//  PlayerPath
//
//  Centralized UserDefaults keys + threshold for the post-recording trimmer workflow.
//  These keys are read from multiple call sites (Quick Record, coach upload) and bound
//  in settings via @AppStorage; a typo'd raw-string key would silently read `false`
//  with no compiler error. Funneling all sites through these constants removes that bug.
//  String values must stay stable — they're already persisted in production.
//  (Mirrors NotificationPrefKeys.)
//

import Foundation

enum TrimmerPrefKeys {
    /// Always show the trimmer after recording, regardless of clip length. Default off.
    static let autoShowTrimmer = "autoShowTrimmer"
    /// Auto-skip the trimmer for clips shorter than `shortClipThreshold`. Default on.
    static let skipTrimmerForShortClips = "skipTrimmerForShortClips"
    /// Clips shorter than this many seconds count as "short" for auto-skip.
    static let shortClipThreshold: Double = 15
}
