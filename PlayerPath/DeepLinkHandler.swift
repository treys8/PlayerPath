//
//  DeepLinkHandler.swift
//  PlayerPath
//
//  Created by Assistant on 12/05/25.
//  Handles deep links for coach invitations and other app navigation
//

import SwiftUI
import Combine
import FirebaseAuth

/// Manages deep link handling for the PlayerPath app
@MainActor
class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingInvitationID: String?
    @Published var shouldShowInvitation = false

    private init() {}

    /// Handles incoming URL from deep link or universal link
    /// - Parameter url: The URL to handle
    /// - Returns: True if the URL was handled successfully
    func handle(url: URL) -> Bool {
        print("🔗 Deep link received: \(url.absoluteString)")

        // Parse the URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("❌ Failed to parse URL components")
            return false
        }

        // Handle playerpath:// scheme
        if components.scheme == "playerpath" {
            return handleCustomScheme(components: components)
        }

        // Handle https://playerpath.app/ universal links
        if components.scheme == "https" && components.host == "playerpath.app" {
            return handleUniversalLink(components: components)
        }

        print("❌ Unknown URL scheme: \(components.scheme ?? "none")")
        return false
    }

    /// Handles custom scheme URLs (playerpath://...)
    private func handleCustomScheme(components: URLComponents) -> Bool {
        // Format: playerpath://invitation/{invitationId}
        // Or: playerpath://folder/{folderId}

        let pathComponents = components.path.split(separator: "/")

        guard pathComponents.count >= 2 else {
            print("❌ Invalid path: \(components.path)")
            return false
        }

        let action = String(pathComponents[0])
        let identifier = String(pathComponents[1])

        switch action {
        case "invitation":
            return handleInvitation(invitationId: identifier)

        case "folder":
            return handleFolder(folderId: identifier)

        default:
            print("❌ Unknown action: \(action)")
            return false
        }
    }

    /// Handles universal links (https://playerpath.app/...)
    private func handleUniversalLink(components: URLComponents) -> Bool {
        // Format: https://playerpath.app/invitation/{invitationId}

        let pathComponents = components.path.split(separator: "/")

        guard pathComponents.count >= 2 else {
            print("❌ Invalid path: \(components.path)")
            return false
        }

        let action = String(pathComponents[0])
        let identifier = String(pathComponents[1])

        switch action {
        case "invitation":
            return handleInvitation(invitationId: identifier)

        case "folder":
            return handleFolder(folderId: identifier)

        default:
            print("❌ Unknown action: \(action)")
            return false
        }
    }

    /// Handles invitation deep links
    private func handleInvitation(invitationId: String) -> Bool {
        print("📨 Handling invitation: \(invitationId)")

        // Check if user is signed in
        guard Auth.auth().currentUser != nil else {
            print("⚠️ User not signed in, saving invitation for later")
            // Save the invitation ID to process after sign in
            UserDefaults.standard.set(invitationId, forKey: "pendingInvitationId")
            return true
        }

        // Set the pending invitation to show in the UI
        pendingInvitationID = invitationId
        shouldShowInvitation = true

        print("✅ Invitation ready to display")
        return true
    }

    /// Handles folder deep links
    private func handleFolder(folderId: String) -> Bool {
        print("📁 Handling folder: \(folderId)")

        // TODO: Navigate to specific folder
        // This would require coordination with the navigation system

        return true
    }

    /// Checks for pending invitation after user signs in
    func checkPendingInvitation() {
        if let invitationId = UserDefaults.standard.string(forKey: "pendingInvitationId") {
            print("📨 Processing pending invitation: \(invitationId)")
            UserDefaults.standard.removeObject(forKey: "pendingInvitationId")
            _ = handleInvitation(invitationId: invitationId)
        }
    }

    /// Clears the current pending invitation
    func clearPendingInvitation() {
        pendingInvitationID = nil
        shouldShowInvitation = false
    }
}

/// View modifier to handle deep link invitations
struct DeepLinkInvitationHandler: ViewModifier {
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingInvitationDetail = false

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                _ = deepLinkHandler.handle(url: url)
            }
            .onChange(of: deepLinkHandler.shouldShowInvitation) { _, shouldShow in
                if shouldShow {
                    showingInvitationDetail = true
                }
            }
            .onChange(of: authManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    // Check for pending invitations after sign in
                    deepLinkHandler.checkPendingInvitation()
                }
            }
            .sheet(isPresented: $showingInvitationDetail) {
                if let invitationId = deepLinkHandler.pendingInvitationID {
                    InvitationDetailView(invitationId: invitationId)
                        .onDisappear {
                            deepLinkHandler.clearPendingInvitation()
                        }
                }
            }
    }
}

extension View {
    /// Adds deep link invitation handling to the view
    func handleDeepLinkInvitations() -> some View {
        modifier(DeepLinkInvitationHandler())
    }
}

/// View that displays a specific invitation from a deep link
struct InvitationDetailView: View {
    let invitationId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var folderManager = SharedFolderManager.shared

    @State private var invitation: CoachInvitation?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAccepting = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invitation...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text("Error Loading Invitation")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let invitation = invitation {
                    invitationView(invitation)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Invitation Not Found")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("This invitation may have expired or been removed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Coach Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadInvitation()
            }
        }
    }

    @ViewBuilder
    private func invitationView(_ invitation: CoachInvitation) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("You're Invited!")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("from \(invitation.athleteName)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Folder info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(invitation.folderName)
                            .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Permissions (if available)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text("As a coach, you'll be able to view and collaborate on videos in this folder.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Accept button
                Button {
                    Task {
                        await acceptInvitation()
                    }
                } label: {
                    if isAccepting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Accept Invitation")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAccepting)
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func loadInvitation() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let coachEmail = authManager.userEmail else {
                errorMessage = "Please sign in to view this invitation"
                isLoading = false
                return
            }

            // Fetch the specific invitation
            let invitations = try await folderManager.checkPendingInvitations(forEmail: coachEmail)

            // Find the matching invitation
            if let foundInvitation = invitations.first(where: { $0.id == invitationId }) {
                invitation = foundInvitation
            } else {
                errorMessage = "Invitation not found or already accepted"
            }

        } catch {
            errorMessage = "Failed to load invitation: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func acceptInvitation() async {
        guard let invitation = invitation else { return }

        isAccepting = true

        do {
            try await folderManager.acceptInvitation(invitation)

            Haptics.success()

            // Show success briefly then dismiss
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            dismiss()

        } catch {
            errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
            Haptics.error()
        }

        isAccepting = false
    }
}
