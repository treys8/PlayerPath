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
import FirebaseFirestore
import TipKit
import os

private let appLog = Logger(subsystem: "com.playerpath.app", category: "App")

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

    /// Shared model container.
    ///
    /// NOTE on versioned migration: SwiftData's VersionedSchema checksum system requires each schema
    /// version to embed its own frozen model-type definitions (e.g. SchemaV1.User vs SchemaV2.User
    /// as separate nested classes). Because all schemas here reference the same live model classes,
    /// their checksums are identical and using a MigrationPlan causes "Duplicate version checksums
    /// detected" at launch. Since no production users exist on V1, we use the simple unversioned
    /// container which handles lightweight property additions/removals automatically.
    ///
    /// When real users exist and a true schema change is needed, revisit with nested model types
    /// inside each VersionedSchema enum per Apple's WWDC pattern.
    static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(SchemaV15.models))
        } catch {
            // Last resort: try an in-memory container so the app can launch and show
            // an error instead of crash-looping. If even that fails, we have no choice
            // but to terminate.
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: Schema(SchemaV15.models), configurations: [config])
            } catch {
                // Intentional fatalError: the app cannot function without a ModelContainer.
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }()

    // Firebase is configured in PlayerPathAppDelegate.didFinishLaunchingWithOptions
    // (which runs before App.init) so that App Check is set up before FirebaseApp.configure().
    // Do NOT add a duplicate FirebaseApp.configure() here.

    init() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            appLog.error("Failed to configure TipKit: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ScenePhaseSaveHandler(scenePhase: scenePhase) {
                PlayerPathMainView()
                    .environment(\.navigationCoordinator, navigationCoordinator)
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToStatistics)) { (notification: Notification) in
                        if let athleteId = notification.object as? String {
                            appLog.debug("Received navigateToStatistics for id: \(athleteId)")
                            navigationCoordinator.navigateToStatistics(athleteId: athleteId)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForGame)) { (notification: Notification) in
                        if let gameId = notification.object as? String {
                            appLog.debug("Received startRecordingForGame for id: \(gameId)")
                            navigationCoordinator.navigateToRecordGame(gameId: gameId)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForPractice)) { (notification: Notification) in
                        if let practiceId = notification.object as? String {
                            appLog.debug("Received startRecordingForPractice for id: \(practiceId)")
                            navigationCoordinator.navigateToRecordPractice(practiceId: practiceId)
                        }
                    }
                    // Fix AF: Add observers for the three notification names that
                    // PushNotificationService posts but were previously unobserved.
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToWeeklySummary)) { _ in
                        Haptics.light()
                        navigationCoordinator.showWeeklySummary = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToPremiumFeatures)) { _ in
                        // Navigate to Profile tab where subscription management lives
                        Haptics.light()
                        NotificationCenter.default.post(name: .switchTab, object: MainTab.more.rawValue)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToCloudStorage)) { _ in
                        // Navigate to Profile tab where cloud storage settings live
                        Haptics.light()
                        NotificationCenter.default.post(name: .switchTab, object: MainTab.more.rawValue)
                    }
                    // Fix AH: Present InvitationDetailView when an invitation deep link is received.
                    // Previously navigationCoordinator.showInvitation was set but never observed.
                    .sheet(isPresented: Binding(
                        get: { navigationCoordinator.showInvitation },
                        set: { if !$0 { navigationCoordinator.showInvitation = false } }
                    )) {
                        if let invitationId = navigationCoordinator.selectedInvitationId {
                            InvitationDetailView(invitationId: invitationId)
                                .onDisappear {
                                    navigationCoordinator.resetNavigation()
                                }
                        }
                    }
            }
                // Note: Notification permission is requested in MainTabView.task, post-onboarding.
                // Deep link handling (.onOpenURL) lives in PlayerPathMainView where
                // authManager is available for pre-auth deferral.
        }
        .modelContainer(PlayerPathApp.sharedModelContainer)
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

    var selectedAthleteId: String?
    var selectedGameId: String?
    var selectedPracticeId: String?
    var selectedInvitationId: String?

    /// Deep link that arrived before the user was authenticated.
    /// Consumed by AuthenticatedFlow after sign-in completes.
    var pendingDeepLink: DeepLinkIntent?

    func navigateToStatistics(athleteId: String) {
        Haptics.light()
        selectedAthleteId = athleteId
        showStatistics = true
    }

    func navigateToRecordGame(gameId: String) {
        Haptics.light()
        selectedGameId = gameId
        showVideoRecorder = true
    }

    func navigateToRecordPractice(practiceId: String) {
        Haptics.light()
        selectedPracticeId = practiceId
        showVideoRecorder = true
    }

    func navigateToInvitation(invitationId: String) {
        Haptics.light()
        selectedInvitationId = invitationId
        showInvitation = true
    }

    func handle(_ intent: DeepLinkIntent) {
        switch intent {
        case .statistics(let id):
            navigateToStatistics(athleteId: id)
        case .recordGame(let id):
            navigateToRecordGame(gameId: id)
        case .recordPractice(let id):
            navigateToRecordPractice(practiceId: id)
        case .invitation(let id):
            navigateToInvitation(invitationId: id)
        case .folder(let id):
            Haptics.light()
            NotificationCenter.default.post(name: .navigateToCoachFolder, object: id)
        }
    }

    func resetNavigation() {
        showStatistics = false
        showVideoRecorder = false
        showWeeklySummary = false
        showInvitation = false
        selectedAthleteId = nil
        selectedGameId = nil
        selectedPracticeId = nil
        selectedInvitationId = nil
        pendingDeepLink = nil
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
    /// playerpath://statistics?athleteId=...
    /// playerpath://record/game?gameId=...
    /// playerpath://record/practice?practiceId=...
    /// playerpath://invitation/{invitationId}
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
        appLog.debug("Scene phase changed: \(String(describing: oldPhase)) -> \(String(describing: newPhase))")

        switch newPhase {
        case .active:
            appLog.info("App became active")

            // Refresh entitlements each time the app returns to foreground to catch
            // renewals, expirations, or revocations that occurred in the background.
            Task { await StoreKitManager.shared.updateEntitlements() }
            // Track session for review prompt eligibility
            Task { ReviewPromptManager.shared.recordSession() }
            // Trigger immediate sync to catch changes made while backgrounded
            Task {
                let descriptor = FetchDescriptor<User>()
                if let user = try? modelContext.fetch(descriptor).first,
                   user.firebaseAuthUid != nil {
                    do {
                        try await SyncCoordinator.shared.syncAll(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "PlayerPathApp.foregroundSync", showAlert: true)
                    }
                }
            }
            lastSavedPhase = .active

        case .inactive:
            appLog.info("App became inactive — saving data")
            saveModelContext()
            lastSavedPhase = .inactive

        case .background:
            appLog.info("App moved to background — saving data")
            saveModelContext()
            lastSavedPhase = .background

        @unknown default:
            break
        }
    }

    private func saveModelContext() {
        // Only save if there are changes
        guard modelContext.hasChanges else {
            appLog.debug("No changes to save")
            return
        }

        do {
            try modelContext.save()
            appLog.debug("Model context saved successfully")
        } catch {
            appLog.warning("Failed to save model context: \(error.localizedDescription)")
            // Log the error but don't crash the app
        }
    }
}
