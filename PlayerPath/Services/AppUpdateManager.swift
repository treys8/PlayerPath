//
//  AppUpdateManager.swift
//  PlayerPath
//
//  Checks for forced app updates and tracks What's New version display.
//  Reads from Firestore `appConfig/current` document.
//

import Foundation
import Combine
import FirebaseFirestore
import os

private let updateLog = Logger(subsystem: "com.playerpath.app", category: "AppUpdate")

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    @Published var requiresUpdate = false
    @Published var showWhatsNew = false
    @Published var whatsNewItems: [String] = []

    private(set) var minimumVersion: String?
    private(set) var latestVersion: String?
    private(set) var updateURL: String?

    private init() {}

    /// Checks Firestore for minimum version and What's New content.
    /// Call on app launch after auth state is resolved.
    func checkOnLaunch() async {
        let db = Firestore.firestore()

        do {
            let snapshot = try await db.collection(FC.appConfig).document("current").getDocument()
            guard let data = snapshot.data() else {
                updateLog.debug("No appConfig/current document found — skipping update check")
                return
            }

            // Force update check
            if let minVersion = data["minimumVersion"] as? String {
                minimumVersion = minVersion
                latestVersion = data["latestVersion"] as? String
                updateURL = data["updateURL"] as? String

                let currentVersion = Bundle.main.appVersion
                if isVersion(currentVersion, lessThan: minVersion) {
                    requiresUpdate = true
                    updateLog.warning("Force update required: current \(currentVersion) < minimum \(minVersion)")
                    return // Don't show What's New if update is required
                }
            }

            // What's New check
            if let items = data["whatsNew"] as? [String],
               let whatsNewVersion = data["whatsNewVersion"] as? String,
               !items.isEmpty {
                let currentVersion = Bundle.main.appVersion
                // Only show if What's New is for the current version and user hasn't seen it
                if whatsNewVersion == currentVersion && !hasSeenWhatsNew(for: whatsNewVersion) {
                    whatsNewItems = items
                    showWhatsNew = true
                    updateLog.info("Showing What's New for version \(whatsNewVersion)")
                }
            }
        } catch {
            // Non-fatal — don't block app launch for config fetch failure
            updateLog.warning("Failed to fetch appConfig: \(error.localizedDescription)")
        }
    }

    /// Marks the What's New as seen for the given version.
    func markWhatsNewSeen() {
        let version = Bundle.main.appVersion
        UserDefaults.standard.set(version, forKey: "lastSeenWhatsNewVersion")
        showWhatsNew = false
    }

    // MARK: - Private

    private func hasSeenWhatsNew(for version: String) -> Bool {
        let lastSeen = UserDefaults.standard.string(forKey: "lastSeenWhatsNewVersion")
        return lastSeen == version
    }

    /// Compares two semantic version strings (e.g., "3.24.26" < "3.25.0").
    private func isVersion(_ current: String, lessThan minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(currentParts.count, minimumParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let m = i < minimumParts.count ? minimumParts[i] : 0
            if c < m { return true }
            if c > m { return false }
        }
        return false // equal
    }
}
