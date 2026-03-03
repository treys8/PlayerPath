//
//  RoleBasedViewModifiers.swift
//  PlayerPath
//
//  Created by Assistant on 12/2/25.
//  Role-based UI enforcement for athlete vs coach features
//

import SwiftUI
import Combine

// MARK: - Role-Based View Modifiers

extension View {
    /// Restricts this view to athlete users only
    /// Shows unavailable message for coaches
    func athleteOnly() -> some View {
        modifier(RoleGateModifier(requiredRole: .athlete))
    }

    /// Restricts this view to coach users only
    /// Shows unavailable message for athletes
    func coachOnly() -> some View {
        modifier(RoleGateModifier(requiredRole: .coach))
    }

    /// Requires premium subscription
    /// Shows paywall for non-premium users
    func premiumRequired() -> some View {
        modifier(PremiumGateModifier())
    }

    /// Requires Plus tier or above
    func plusRequired() -> some View {
        modifier(TierGateModifier(requiredTier: .plus))
    }

    /// Requires Pro tier
    func proRequired() -> some View {
        modifier(TierGateModifier(requiredTier: .pro))
    }

}

// MARK: - Role Gate Modifier

struct RoleGateModifier: ViewModifier {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    let requiredRole: UserRole

    func body(content: Content) -> some View {
        if authManager.userRole == requiredRole {
            content
        } else {
            RoleRestrictionView(
                requiredRole: requiredRole,
                currentRole: authManager.userRole
            )
        }
    }
}

// MARK: - Premium Gate Modifier

struct PremiumGateModifier: ViewModifier {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        if authManager.isPremiumUser {
            content
        } else {
            LockedFeatureView(
                icon: "crown.fill",
                iconColor: .yellow,
                title: "Premium Feature",
                subtitle: "Upgrade to unlock this feature",
                buttonLabel: "View Plans"
            ) {
                showingPaywall = true
            }
            .sheet(isPresented: $showingPaywall) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user)
                }
            }
        }
    }
}

// MARK: - Tier Gate Modifier

struct TierGateModifier: ViewModifier {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    let requiredTier: SubscriptionTier
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        if authManager.currentTier >= requiredTier {
            content
        } else {
            LockedFeatureView(
                icon: "crown.fill",
                iconColor: .yellow,
                title: "\(requiredTier.displayName) Feature",
                subtitle: "Upgrade to \(requiredTier.displayName) to unlock this feature",
                buttonLabel: "View Plans"
            ) {
                showingPaywall = true
            }
            .sheet(isPresented: $showingPaywall) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user)
                }
            }
        }
    }
}

// MARK: - Locked Feature View

private struct LockedFeatureView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonLabel: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(buttonLabel, action: action)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Role Restriction View

struct RoleRestrictionView: View {
    let requiredRole: UserRole
    let currentRole: UserRole

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: restrictionIcon)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Not Available")
                .font(.title2)
                .fontWeight(.semibold)

            Text(restrictionMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var restrictionIcon: String {
        switch requiredRole {
        case .athlete:
            return "figure.run"
        case .coach:
            return "person.badge.shield.checkmark"
        }
    }

    private var restrictionMessage: String {
        switch (currentRole, requiredRole) {
        case (.coach, .athlete):
            return "This feature is only available for athlete accounts. As a coach, you can view shared content from athletes who invite you."
        case (.athlete, .coach):
            return "This feature is only available for coach accounts."
        default:
            return "This feature is not available for your account type."
        }
    }
}

// MARK: - Permission Change Observer

/// Observable object that listens for permission changes in real-time
@MainActor final class PermissionChangeObserver: ObservableObject {
    @Published var currentPermissions: FolderPermissions
    @Published var permissionsChanged = false
    @Published var changeMessage: String?

    private let folderID: String
    private var listener: Task<Void, Never>?

    init(folderID: String, initialPermissions: FolderPermissions) {
        self.folderID = folderID
        self.currentPermissions = initialPermissions
    }

    /// Starts listening for permission changes
    /// TODO: Replace with a Firestore snapshot listener on sharedFolders/{folderID}
    /// so that permission revocations are reflected in real time without re-entering the view.
    func startListening(coachID: String) {
        // Fix V: The previous implementation ran an empty 30-second sleep loop that
        // consumed a Task indefinitely without performing any actual permission checks.
        // Removed until the Firestore snapshot listener is implemented.
        print("👂 Permission change listener registered for folder: \(folderID) (snapshot listener not yet implemented)")
    }

    /// Stops listening
    func stopListening() {
        listener?.cancel()
        listener = nil
        print("🔇 Stopped listening for permission changes")
    }

    /// Updates permissions and notifies UI
    func updatePermissions(_ newPermissions: FolderPermissions) {
        let oldPermissions = currentPermissions
        currentPermissions = newPermissions

        // Check what changed
        if oldPermissions.canUpload != newPermissions.canUpload {
            changeMessage = newPermissions.canUpload
                ? "You can now upload videos"
                : "Upload permission removed"
            permissionsChanged = true
        } else if oldPermissions.canDelete != newPermissions.canDelete {
            changeMessage = newPermissions.canDelete
                ? "You can now delete videos"
                : "Delete permission removed"
            permissionsChanged = true
        }
    }

    deinit {
        listener?.cancel()
        listener = nil
    }
}

// MARK: - Permission Change Alert Modifier

struct PermissionChangeAlert: ViewModifier {
    @ObservedObject var observer: PermissionChangeObserver

    func body(content: Content) -> some View {
        content
            .alert(
                "Permissions Changed",
                isPresented: Binding(
                    get: { observer.permissionsChanged },
                    set: { newValue in
                        observer.permissionsChanged = newValue
                        if !newValue {
                            observer.changeMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    observer.permissionsChanged = false
                    observer.changeMessage = nil
                }
            } message: {
                if let message = observer.changeMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    /// Shows alert when permissions change
    func alertOnPermissionChange(observer: PermissionChangeObserver) -> some View {
        self.modifier(PermissionChangeAlert(observer: observer))
    }
}

// MARK: - Preview

#Preview("Athlete Only") {
    Text("Athlete Dashboard")
        .athleteOnly()
        .environmentObject(ComprehensiveAuthManager())
}

#Preview("Coach Only") {
    Text("Coach Dashboard")
        .coachOnly()
        .environmentObject(ComprehensiveAuthManager())
}

#Preview("Premium Required") {
    VStack {
        Text("Create Shared Folder")
    }
    .premiumRequired()
    .environmentObject(ComprehensiveAuthManager())
}

