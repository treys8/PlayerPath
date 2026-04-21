//
//  PlayerPathApp.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Combine
import TipKit
import os

private let appLog = Logger(subsystem: "com.playerpath.app", category: "App")

/// Provides a shared `NavigationCoordinator` via the environment so views can react
/// to app-wide navigation requests (e.g., invitation deep links from push taps
/// or `playerpath://` URLs). Tab-switching deep links are handled by posting
/// `Notification.Name` events that `MainTabView` / `CoachTabView` observe.
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
            return try ModelContainer(for: Schema(SchemaV17.models))
        } catch {
            // Last resort: try an in-memory container so the app can launch and show
            // an error instead of crash-looping. If even that fails, we have no choice
            // but to terminate.
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: Schema(SchemaV17.models), configurations: [config])
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
                .displayFrequency(.daily),
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
                    // Game/practice reminder push taps land on the Videos tab where
                    // the record button lives. The tab switch is handled by
                    // MainTabView's existing `.presentVideoRecorder` observer.
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForGame)) { _ in
                        appLog.debug("Received startRecordingForGame — switching to Videos tab")
                        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForPractice)) { _ in
                        appLog.debug("Received startRecordingForPractice — switching to Videos tab")
                        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
                    }
                    // No dedicated WeeklySummaryView exists; route to Stats tab as the
                    // closest existing screen so the push CTA isn't a no-op.
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToWeeklySummary)) { _ in
                        Haptics.light()
                        NotificationCenter.default.post(name: .switchTab, object: MainTab.stats.rawValue)
                    }
                    // `.navigateToCloudStorage` is handled inside MainTabView so it can
                    // push StorageSettingsView onto the More tab's navigation path.
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
    var showInvitation = false
    var selectedInvitationId: String?

    /// Deep link that arrived before the user was authenticated.
    /// Consumed by AuthenticatedFlow after sign-in completes.
    var pendingDeepLink: DeepLinkIntent?

    func navigateToInvitation(invitationId: String) {
        Haptics.light()
        selectedInvitationId = invitationId
        showInvitation = true
    }

    /// Route a deep link to its destination. Tab-switching intents post
    /// notifications that `MainTabView` observes; the invitation intent
    /// drives the sheet owned by this coordinator.
    func handle(_ intent: DeepLinkIntent) {
        switch intent {
        case .statistics:
            Haptics.light()
            NotificationCenter.default.post(name: .switchTab, object: MainTab.stats.rawValue)
        case .recordGame, .recordPractice:
            NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
        case .invitation(let id):
            navigateToInvitation(invitationId: id)
        case .folder(let id):
            Haptics.light()
            // Post both role-scoped notifications — only the active tab bar observes its own.
            NotificationCenter.default.post(name: .navigateToCoachFolder, object: id)
            NotificationCenter.default.post(name: .navigateToSharedFolder, object: id)
        }
    }

    func resetNavigation() {
        showInvitation = false
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
        func firstPathSegment() -> String? {
            url.path.split(separator: "/").first.map(String.init)
        }

        switch (host, url.path.lowercased()) {
        case ("statistics", _):
            if let id = value("athleteId"), !id.isEmpty { self = .statistics(athleteId: id); return }
        case ("record", "/game"):
            if let id = value("gameId"), !id.isEmpty { self = .recordGame(gameId: id); return }
        case ("record", "/practice"):
            if let id = value("practiceId"), !id.isEmpty { self = .recordPractice(practiceId: id); return }
        case ("invitation", _):
            // Format: playerpath://invitation/{invitationId}
            if let id = firstPathSegment(), !id.isEmpty {
                self = .invitation(invitationId: id)
                return
            }
        case ("folder", _):
            // Format: playerpath://folder/{folderId}
            if let id = firstPathSegment(), !id.isEmpty {
                self = .folder(folderId: id)
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

            // Mark the foreground transition so ActivityNotificationService can
            // suppress in-app banners for notifications the user already saw as
            // FCM lock-screen banners while the app was backgrounded.
            ActivityNotificationService.shared.noteAppDidBecomeActive()

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

        case .inactive:
            appLog.info("App became inactive — saving data")
            saveModelContext()

        case .background:
            appLog.info("App moved to background — saving data")
            saveModelContext()

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
