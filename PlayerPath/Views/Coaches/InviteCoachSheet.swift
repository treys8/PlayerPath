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
                                .fill(Color.brandNavy.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(.brandNavy)
                        }

                        Text("Invite a Coach")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Share your videos with a coach for feedback and guidance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Form
                    VStack(spacing: 16) {
                        // Coach Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach's Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("Enter coach's name", text: $coachName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                        }

                        // Coach Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach's Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("coach@example.com", text: $coachEmail)
                                .textFieldStyle(.roundedBorder)
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
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

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
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    // Info box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.brandNavy)

                        Text("Your coach will receive an email invitation. Once they accept, they'll be able to view your shared videos and send you practice content.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.brandNavy.opacity(0.1))
                    .cornerRadius(12)
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
                        .background(canSend ? Color.brandNavy : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(!canSend)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
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

                // Require Pro tier to invite coaches
                guard authManager.hasCoachingAccess else {
                    throw SharedFolderError.coachingRequired
                }

                // Create invitation only — folders are created server-side when the coach accepts.
                // This avoids orphaned folders if the coach never accepts or is at their limit.
                _ = try await FirestoreManager.shared.createInvitation(
                    athleteID: userID,
                    athleteName: athlete.name,
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
                errorMessage = "Failed to send invitation: \(error.localizedDescription)"
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

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isOn ? .brandNavy : .gray)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(isDisabled)
        }
    }
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
