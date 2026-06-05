//
//  InviteCoachSheet.swift
//  PlayerPath
//
//  Allows athletes to invite coaches by email
//  Premium feature for coach sharing
//

import SwiftUI
import SwiftData

struct InviteCoachSheet: View {
    let athlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var coachEmail = ""
    @State private var coachName = ""
    @State private var selectedPermissions = FolderPermissions.default
    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    private enum Field: Hashable { case name, email }
    @FocusState private var focusedField: Field?

    private var isValidEmail: Bool {
        coachEmail.isValidEmail
    }

    private var canSend: Bool {
        isValidEmail && !coachName.isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(ppAccent.opacity(0.12))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(ppAccent)
                        }

                        Text("Invite a Coach")
                            .font(.headingLarge)
                            .foregroundColor(Theme.textPrimary)

                        Text("Share your videos with a coach for feedback and guidance")
                            .font(.bodyMedium)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Form
                    VStack(spacing: 16) {
                        // Coach Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach's Name")
                                .font(.headingSmall)
                                .foregroundColor(Theme.textSecondary)

                            TextField("Enter coach's name", text: $coachName)
                                .ppFieldStyle()
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                        }

                        // Coach Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach's Email")
                                .font(.headingSmall)
                                .foregroundColor(Theme.textSecondary)

                            TextField("coach@example.com", text: $coachEmail)
                                .ppFieldStyle()
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }

                            if !coachEmail.isEmpty && !isValidEmail {
                                Text("Please enter a valid email address")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // Permissions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Coach Permissions")
                                .font(.headingSmall)
                                .foregroundColor(Theme.textSecondary)

                            VStack(spacing: 8) {
                                PermissionToggle(
                                    title: "View Videos",
                                    icon: "eye",
                                    isOn: .constant(true), // Always on
                                    isDisabled: true
                                )

                                PermissionToggle(
                                    title: "Upload Practice Videos",
                                    icon: "arrow.up.circle",
                                    isOn: $selectedPermissions.canUpload
                                )

                                PermissionToggle(
                                    title: "Add Comments",
                                    icon: "bubble.left",
                                    isOn: $selectedPermissions.canComment
                                )
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                                    .fill(Theme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                                    .strokeBorder(Theme.divider, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Info box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(ppAccent)

                        Text("Your coach will receive an email invitation. Once they accept, they'll be able to view your shared videos and send you practice content.")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                            .fill(ppAccent.opacity(0.1))
                    )
                    .padding(.horizontal)

                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)

                    // Send Button
                    Button(action: sendInvitation) {
                        HStack(spacing: 10) {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isSending ? "Sending..." : "Send Invitation")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                                .fill(canSend ? ppAccent : Theme.textTertiary)
                        )
                        .shadow(color: canSend ? ppAccent.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .disabled(!canSend)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(Theme.surface)
            .tint(ppAccent)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toast(isPresenting: $showingSuccess, message: "Invitation Sent")
            .onChange(of: showingSuccess) { _, new in
                if !new { dismiss() }
            }
        }
    }

    private func sendInvitation() {
        guard canSend else { return }

        isSending = true
        errorMessage = nil

        Task { @MainActor in
            do {
                guard let userID = authManager.userID else {
                    throw NSError(domain: "InviteCoach", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }

                // Prevent self-invitation
                if let userEmail = authManager.userEmail,
                   coachEmail.lowercased() == userEmail.lowercased() {
                    throw NSError(domain: "InviteCoach", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "You cannot send an invitation to yourself."
                    ])
                }

                // Check for existing pending invitation to this coach from this athlete
                if try await FirestoreManager.shared.hasPendingInvitation(athleteID: userID, coachEmail: coachEmail) {
                    throw NSError(domain: "InviteCoach", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "An invitation has already been sent to this coach."
                    ])
                }

                // Make sure Firestore has our latest tier before createInvitation's
                // rules check runs, so a just-changed subscription is reflected and a
                // stale-tier write doesn't get rejected server-side.
                try? await authManager.syncSubscriptionTierToFirestoreAndWait()

                // Require Pro tier to invite coaches
                guard authManager.hasCoachingAccess else {
                    throw SharedFolderError.coachingRequired
                }

                // Create invitation only — folders are created server-side when the coach accepts.
                // This avoids orphaned folders if the coach never accepts or is at their limit.
                _ = try await FirestoreManager.shared.createInvitation(
                    athleteID: userID,
                    athleteName: athlete.name,
                    athleteUUID: athlete.id.uuidString,
                    personGroupID: (athlete.personGroupID ?? athlete.id).uuidString,
                    coachEmail: coachEmail.lowercased(),
                    permissions: selectedPermissions
                )

                // Save coach locally (pending status) — safe on MainActor
                let coach = Coach(
                    name: coachName,
                    email: coachEmail.lowercased()
                )
                coach.needsSync = true
                coach.athlete = athlete
                coach.invitationSentAt = Date()
                coach.lastInvitationStatus = "pending"
                modelContext.insert(coach)
                ErrorHandlerService.shared.saveContext(modelContext, caller: "InviteCoachSheet.sendInvitation")

                isSending = false
                Haptics.success()
                showingSuccess = true
            } catch {
                isSending = false
                let nsError = error as NSError
                if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                    // Firestore rules rejected the write — athlete no longer has Pro.
                    errorMessage = "A Pro subscription is required to invite a coach. Upgrade to Pro and try again."
                } else {
                    errorMessage = "Failed to send invitation: \(error.localizedDescription)"
                }
                ErrorHandlerService.shared.handle(error, context: "InviteCoachSheet.sendInvitation", showAlert: false)
            }
        }
    }
}

// MARK: - Permission Toggle

private struct PermissionToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isOn ? ppAccent : Theme.textTertiary)
                .frame(width: 24)

            Text(title)
                .font(.bodyMedium)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ppAccent)
                .disabled(isDisabled)
        }
    }
}

// MARK: - Field Style

/// Cream-era text-field chrome: white card surface with a hairline divider
/// border, replacing the system `.roundedBorder` look so fields sit on the
/// Theme.surface background consistently.
private struct PPFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.bodyLarge)
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
    }
}

private extension View {
    func ppFieldStyle() -> some View { modifier(PPFieldStyle()) }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: Athlete.self, Coach.self, configurations: config) else {
        return Text("Failed")
    }

    let athlete = Athlete(name: "Test Athlete")
    container.mainContext.insert(athlete)

    return InviteCoachSheet(athlete: athlete)
        .modelContainer(container)
        .environmentObject(ComprehensiveAuthManager())
}
