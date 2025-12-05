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
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Premium Feature")
                            .font(.headline)
                        Text("Upgrade to unlock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .sheet(isPresented: $showingPaywall) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user)
                }
            }
        }
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
    func startListening(coachID: String) {
        listener = Task {
            // TODO: Implement Firebase realtime listener
            // For now, this is a placeholder
            print("👂 Started listening for permission changes on folder: \(folderID)")

            // Simulate permission check every 30 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                // In production, this would be a Firebase snapshot listener
                // firestore.observeFolder(folderID)
            }
        }
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

