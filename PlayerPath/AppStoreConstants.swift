//
//  AppStoreConstants.swift
//  PlayerPath
//
//  App Store identity used by the "Rate" and "Share" growth rows.
//

import Foundation

enum AppStoreConstants {
    /// Numeric App Store ID for PlayerPath.
    ///
    /// ⚠️ TODO: Set this to the app's numeric Apple ID before shipping the
    /// Rate / Share rows. Find it in App Store Connect →
    /// App → General → App Information → "Apple ID" (a ~10-digit number).
    /// Until it is set, `isConfigured` is false and the Rate/Share rows stay
    /// hidden so nothing broken ships.
    static let appStoreID = "" // e.g. "1234567890"

    /// True once a real App Store ID has been filled in.
    static var isConfigured: Bool { !appStoreID.isEmpty }

    /// Public App Store product page (for sharing).
    static var appStoreURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }

    /// Deep link that opens the App Store directly to the write-a-review screen.
    static var writeReviewURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}
