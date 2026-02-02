//
//  PlayerPathApp.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UserNotifications
import Combine
import FirebaseCore

/// Provides a shared `NavigationCoordinator` via the environment so views can react
/// to app-wide navigation requests (e.g., from notifications or deep links).
///
/// This file also subscribes to several Notification.Name events to trigger navigation:
/// - `.navigateToStatistics` (object: String athleteId)
/// - `.startRecordingForGame` (object: String gameId)
/// - `.startRecordingForPractice` (object: String practiceId)
private struct NavigationCoordinatorKey: EnvironmentKey {
    static let defaultValue = NavigationCoordinator()
}

extension EnvironmentValues {
    var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}

@main
struct PlayerPathApp: App {
    @UIApplicationDelegateAdaptor(PlayerPathAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    // State for handling notification-based navigation
    @State private var navigationCoordinator = NavigationCoordinator()

    // Initialize Firebase before anything else
    init() {
        // Configure Firebase as early as possible
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            #if DEBUG
            print("🔥 Firebase configured in App init")
            #endif
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ScenePhaseSaveHandler(scenePhase: scenePhase) {
                PlayerPathMainView()
                    .environment(\.navigationCoordinator, navigationCoordinator)
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToStatistics)) { (notification: Notification) in
                        if let athleteId = notification.object as? String {
                            #if DEBUG
                            print("🔔 Received navigateToStatistics for id: \(athleteId)")
                            #endif
                            Haptics.light()
                            navigationCoordinator.selectedAthleteId = athleteId
                            navigationCoordinator.showStatistics = true
                            // Handlers in views should call navigationCoordinator.resetNavigation() after navigating.
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForGame)) { (notification: Notification) in
                        if let gameId = notification.object as? String {
                            #if DEBUG
                            print("🔔 Received startRecordingForGame for id: \(gameId)")
                            #endif
                            Haptics.light()
                            navigationCoordinator.selectedGameId = gameId
                            navigationCoordinator.showVideoRecorder = true
                            // Handlers in views should call navigationCoordinator.resetNavigation() after navigating.
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForPractice)) { (notification: Notification) in
                        if let practiceId = notification.object as? String {
                            #if DEBUG
                            print("🔔 Received startRecordingForPractice for id: \(practiceId)")
                            #endif
                            Haptics.light()
                            navigationCoordinator.selectedPracticeId = practiceId
                            navigationCoordinator.showVideoRecorder = true
                            // Handlers in views should call navigationCoordinator.resetNavigation() after navigating.
                        }
                    }
            }
                .onOpenURL { url in
                    #if DEBUG
                    print("🔗 OpenURL: \(url.absoluteString)")
                    #endif
                    if let intent = DeepLinkIntent(url: url) {
                        Haptics.light()
                        switch intent {
                        case .statistics(let athleteId):
                            navigationCoordinator.selectedAthleteId = athleteId
                            navigationCoordinator.showStatistics = true
                        case .recordGame(let gameId):
                            navigationCoordinator.selectedGameId = gameId
                            navigationCoordinator.showVideoRecorder = true
                        case .recordPractice(let practiceId):
                            navigationCoordinator.selectedPracticeId = practiceId
                            navigationCoordinator.showVideoRecorder = true
                        case .invitation(let invitationId):
                            navigationCoordinator.selectedInvitationId = invitationId
                            navigationCoordinator.showInvitation = true
                        case .folder(let folderId):
                            navigationCoordinator.selectedFolderId = folderId
                            navigationCoordinator.showFolder = true
                        }
                        // Views should call navigationCoordinator.resetNavigation() after handling.
                    }
                }
                .task {
                    // Request notification permission early (non-blocking)
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        #if DEBUG
                        print("🔔 Notifications authorization granted: \(granted)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔴 Notification authorization error: \(error)")
                        #endif
                    }
                }
        }
        .modelContainer(for: [
            User.self,
            Athlete.self,
            Season.self,
            Game.self,
            Practice.self,
            PracticeNote.self,
            VideoClip.self,
            PlayResult.self,
            AthleteStatistics.self,
            GameStatistics.self,
            UserPreferences.self,
            OnboardingProgress.self,
            PendingUpload.self
        ])
    }
}

// MARK: - Navigation Coordinator

@MainActor
@Observable
final class NavigationCoordinator {
    var showStatistics = false
    var showVideoRecorder = false
    var showWeeklySummary = false
    var showInvitation = false
    var showFolder = false

    var selectedAthleteId: String?
    var selectedGameId: String?
    var selectedPracticeId: String?
    var selectedInvitationId: String?
    var selectedFolderId: String?

    func resetNavigation() {
        showStatistics = false
        showVideoRecorder = false
        showWeeklySummary = false
        showInvitation = false
        showFolder = false
        selectedAthleteId = nil
        selectedGameId = nil
        selectedPracticeId = nil
        selectedInvitationId = nil
        selectedFolderId = nil
    }
}

// MARK: - Deep Link Intent

/// Represents supported deep link intents for the app.
enum DeepLinkIntent {
    case statistics(athleteId: String)
    case recordGame(gameId: String)
    case recordPractice(practiceId: String)
    case invitation(invitationId: String)
    case folder(folderId: String)
}

extension DeepLinkIntent {
    /// Initialize from a URL of the form:
    /// playerpath://statistics?athleteId=... ,
    /// playerpath://record/game?gameId=... ,
    /// playerpath://record/practice?practiceId=... ,
    /// playerpath://invitation/{invitationId} ,
    /// playerpath://folder/{folderId}
    init?(url: URL) {
        guard let host = url.host?.lowercased() else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        func value(_ name: String) -> String? { queryItems.first(where: { $0.name == name })?.value }

        let path = url.path
        let pathComponents = path.split(separator: "/").map(String.init)

        switch (host, url.path.lowercased()) {
        case ("statistics", _):
            if let id = value("athleteId"), !id.isEmpty { self = .statistics(athleteId: id); return }
        case ("record", "/game"):
            if let id = value("gameId"), !id.isEmpty { self = .recordGame(gameId: id); return }
        case ("record", "/practice"):
            if let id = value("practiceId"), !id.isEmpty { self = .recordPractice(practiceId: id); return }
        case ("invitation", _):
            // Format: playerpath://invitation/{invitationId}
            if pathComponents.count >= 1, !pathComponents[0].isEmpty {
                self = .invitation(invitationId: pathComponents[0])
                return
            }
        case ("folder", _):
            // Format: playerpath://folder/{folderId}
            if pathComponents.count >= 1, !pathComponents[0].isEmpty {
                self = .folder(folderId: pathComponents[0])
                return
            }
        default:
            break
        }
        return nil
    }
}

// MARK: - Scene Phase Save Handler

/// Wrapper view that saves the modelContext when the app goes to background
struct ScenePhaseSaveHandler<Content: View>: View {
    let scenePhase: ScenePhase
    @ViewBuilder let content: () -> Content

    @Environment(\.modelContext) private var modelContext
    @State private var lastSavedPhase: ScenePhase?

    var body: some View {
        content()
            .onChange(of: scenePhase) { oldValue, newValue in
                handleScenePhaseChange(from: oldValue, to: newValue)
            }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        #if DEBUG
        print("📱 Scene phase changed: \(oldPhase) -> \(newPhase)")
        #endif

        switch newPhase {
        case .active:
            #if DEBUG
            print("📱 App became active")
            #endif
            lastSavedPhase = .active

        case .inactive:
            #if DEBUG
            print("📱 App became inactive - saving data...")
            #endif
            saveModelContext()
            lastSavedPhase = .inactive

        case .background:
            #if DEBUG
            print("📱 App moved to background - saving data...")
            #endif
            saveModelContext()
            lastSavedPhase = .background

        @unknown default:
            break
        }
    }

    private func saveModelContext() {
        // Only save if there are changes
        guard modelContext.hasChanges else {
            #if DEBUG
            print("💾 No changes to save")
            #endif
            return
        }

        do {
            try modelContext.save()
            #if DEBUG
            print("✅ Model context saved successfully")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save model context: \(error.localizedDescription)")
            #endif
            // Log the error but don't crash the app
        }
    }
}
