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
import LocalAuthentication
import FirebaseCore
import FirebaseFirestore

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
            return try ModelContainer(for: Schema(SchemaV10.models))
        } catch {
            // Last resort: try an in-memory container so the app can launch and show
            // an error instead of crash-looping. If even that fails, we have no choice
            // but to terminate.
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: Schema(SchemaV10.models), configurations: [config])
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }()

    // Initialize Firebase before anything else
    init() {
        // Configure Firebase as early as possible
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            // Configure Firestore settings immediately after Firebase init,
            // before any code accesses Firestore.firestore() elsewhere.
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings(
                sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100 MB
            )
            Firestore.firestore().settings = settings
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
                        }
                    }
                }
                // Note: Notification permission is requested in MainTabView.task, post-onboarding.
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

    func resetNavigation() {
        showStatistics = false
        showVideoRecorder = false
        showWeeklySummary = false
        showInvitation = false
        selectedAthleteId = nil
        selectedGameId = nil
        selectedPracticeId = nil
        selectedInvitationId = nil
    }
}

// MARK: - Deep Link Intent

/// Represents supported deep link intents for the app.
enum DeepLinkIntent {
    case statistics(athleteId: String)
    case recordGame(gameId: String)
    case recordPractice(practiceId: String)
    case invitation(invitationId: String)
    // folder(folderId:) removed — folder navigation UI is not yet implemented.
    // Folder URLs will fall through to the default nil return and be silently ignored.
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
    @State private var isLocked = false
    @State private var showLockScreen = false

    private var biometricManager: BiometricAuthenticationManager { .shared }

    var body: some View {
        ZStack {
            content()

            if showLockScreen {
                BiometricLockScreen(onUnlock: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showLockScreen = false
                        isLocked = false
                    }
                })
                .transition(.opacity)
            }
        }
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

            // Biometric unlock is handled by BiometricLockScreen.onAppear
            // (no duplicate prompt needed here)

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
                    try? await SyncCoordinator.shared.syncAll(for: user)
                }
            }
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
            // Lock the app if biometric is enabled
            if biometricManager.isBiometricEnabled {
                isLocked = true
                showLockScreen = true
            }
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

// MARK: - Biometric Lock Screen

private struct BiometricLockScreen: View {
    let onUnlock: () -> Void
    @State private var authFailed = false
    @State private var isAuthenticating = false
    @Environment(\.scenePhase) private var scenePhase

    private var biometricManager: BiometricAuthenticationManager { .shared }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("PlayerPath is Locked")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Authenticate with \(biometricManager.biometricTypeName) to continue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if authFailed {
                    VStack(spacing: 12) {
                        Button {
                            authenticate()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                                Text("Try Again")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button {
                            // Disable biometric and unlock. The user will need to
                            // re-enable Face ID/Touch ID in settings if they want it again.
                            biometricManager.disableBiometric()
                            onUnlock()
                        } label: {
                            Text("Disable \(biometricManager.biometricTypeName)")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
            .padding()
        }
        .onAppear {
            authenticate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-trigger biometric when app returns to foreground
            if newPhase == .active && !isAuthenticating {
                authenticate()
            }
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authFailed = false
        Task {
            let email = await biometricManager.authenticateWithSessionBiometric()
            isAuthenticating = false
            if email != nil {
                onUnlock()
            } else {
                authFailed = true
            }
        }
    }
}
