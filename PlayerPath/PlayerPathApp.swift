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
            return try ModelContainer(for: Schema(SchemaV28.models))
        } catch {
            // Last resort: try an in-memory container so the app can launch and show
            // an error instead of crash-looping. If even that fails, we have no choice
            // but to terminate.
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: Schema(SchemaV28.models), configurations: [config])
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
                // .daily (not .immediate) so multiple tips eligible on the same
                // screen — e.g. Photos' layout-toggle + first-cell options tips —
                // don't pop back-to-back. MaxDisplayCount(1) still shows each once.
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
                    // MainTabView's existing `.presentVideoRecorder` observer, while
                    // the id is forwarded via userInfo so VideoClipsView can resolve
                    // it to the Game/Practice and bind the recording's context.
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForGame)) { note in
                        appLog.debug("Received startRecordingForGame — switching to Videos tab")
                        let userInfo = (note.object as? String).map { ["gameId": $0] }
                        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil, userInfo: userInfo)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startRecordingForPractice)) { note in
                        appLog.debug("Received startRecordingForPractice — switching to Videos tab")
                        let userInfo = (note.object as? String).map { ["practiceId": $0] }
                        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil, userInfo: userInfo)
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

    /// Route a deep link to its destination. The invitation intent drives the
    /// sheet owned by this coordinator.
    func handle(_ intent: DeepLinkIntent) {
        switch intent {
        case .invitation(let id):
            navigateToInvitation(invitationId: id)
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
    case invitation(invitationId: String)
}

extension DeepLinkIntent {
    /// Initialize from a URL of the form:
    /// playerpath://invitation/{invitationId}
    init?(url: URL) {
        guard let host = url.host?.lowercased() else { return nil }
        func firstPathSegment() -> String? {
            url.path.split(separator: "/").first.map(String.init)
        }

        switch host {
        case "invitation":
            // Format: playerpath://invitation/{invitationId}
            if let id = firstPathSegment(), !id.isEmpty {
                self = .invitation(invitationId: id)
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
                    } catch is SyncCoordinatorError {
                        // Already syncing or signed out — expected, not user-facing.
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
