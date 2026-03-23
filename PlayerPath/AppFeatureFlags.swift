//
//  AppFeatureFlags.swift
//  PlayerPath
//
//  Centralized feature flags for gating unreleased features.
//  Flip these to true when features are ready for release.
//

import Foundation

enum AppFeatureFlags {
    /// When false, hides all coach-related features:
    /// - Coach role signup (role selection shows "Coming Soon")
    /// - Coaches dashboard card, invitation banner
    /// - Coaches & Shared Folders in More tab and Profile
    /// - Share-to-coach buttons on videos
    /// - Pro tier purchase (coach sharing is the main Pro feature)
    static let isCoachEnabled = false
}
