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
    /// Found in App Store Connect → App → General → App Information → "Apple ID".
    /// Once set, `isConfigured` is true and the Rate/Share growth rows appear.
    static let appStoreID = "6754497342"

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
