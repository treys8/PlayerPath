//
//  CoachNavigationCoordinator.swift
//  PlayerPath
//
//  Programmatic navigation coordinator for the coach experience.
//  Handles tab switching, deep links, and cross-tab navigation.
//

import SwiftUI

enum CoachTab: Int, CaseIterable {
    case dashboard = 0
    case athletes = 1
    case profile = 2

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .athletes: return "Athletes"
        case .profile: return "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .athletes: return "person.3.fill"
        case .profile: return "ellipsis.circle.fill"
        }
    }
}

@MainActor
@Observable
class CoachNavigationCoordinator {
    var selectedTab: CoachTab = .dashboard
    var athletesPath = NavigationPath()
    var dashboardPath = NavigationPath()

    // Pending navigation actions (resolved after folder data loads)
    var pendingFolderID: String?

    /// When set, the next CoachFolderDetailView for this folder should open on this tab.
    var pendingFolderTab: (folderID: String, tab: CoachFolderDetailView.FolderTab)?

    func navigateToFolder(_ folderID: String, folders: [SharedFolder], initialTab: CoachFolderDetailView.FolderTab? = nil) {
        pendingFolderTab = initialTab.map { (folderID: folderID, tab: $0) }
        if let folder = folders.first(where: { $0.id == folderID }) {
            selectedTab = .athletes
            // Reset path then push folder on next tick so tab switch completes first
            athletesPath = NavigationPath()
            Task { @MainActor in
                athletesPath.append(folder)
            }
        } else {
            // Folder not loaded yet — stash for later
            pendingFolderID = folderID
            selectedTab = .athletes
        }
    }

    func navigateToInvitations() {
        selectedTab = .profile
    }

    /// Called when coach folders finish loading to resolve any pending navigation.
    func resolvePendingNavigation(folders: [SharedFolder]) {
        guard let folderID = pendingFolderID else { return }
        pendingFolderID = nil
        if let folder = folders.first(where: { $0.id == folderID }) {
            athletesPath.append(folder)
        }
    }

    // MARK: - State Restoration

    private var tabDefaultsKey: String {
        "CoachLastSelectedTab"
    }

    func saveSelectedTab() {
        UserDefaults.standard.set(selectedTab.rawValue, forKey: tabDefaultsKey)
    }

    func restoreSelectedTab() {
        let saved = UserDefaults.standard.integer(forKey: tabDefaultsKey)
        if let tab = CoachTab(rawValue: saved) {
            selectedTab = tab
        }
    }
}
