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

    private var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return coachEmail.range(of: emailRegex, options: .regularExpression) != nil
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
                                .fill(Color.indigo.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(.indigo)
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
                                .autocapitalization(.none)
                                .autocorrectionDisabled()

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
                            .foregroundColor(.indigo)

                        Text("Your coach will receive an email invitation. Once they accept, they'll be able to view your shared videos and send you practice content.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.indigo.opacity(0.1))
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
                        .background(canSend ? Color.indigo : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(!canSend)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Invitation Sent!", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("An invitation has been sent to \(coachEmail). They'll receive an email with instructions to connect with \(athlete.name).")
            }
        }
    }

    private func sendInvitation() {
        guard canSend else { return }

        isSending = true
        errorMessage = nil

        Task {
            do {
                guard let userID = authManager.userID else {
                    throw NSError(domain: "InviteCoach", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }

                // Create a shared folder for the coach
                let folderName = "\(athlete.name)'s Videos"
                let folderID = try await SharedFolderManager.shared.createFolder(
                    name: folderName,
                    forAthlete: athlete.id.uuidString,
                    isPremium: authManager.isPremiumUser
                )

                // Create invitation for the coach
                _ = try await FirestoreManager.shared.createInvitation(
                    athleteID: athlete.id.uuidString,
                    athleteName: athlete.name,
                    coachEmail: coachEmail.lowercased(),
                    folderID: folderID,
                    folderName: folderName
                )

                // Save coach locally (pending status)
                let coach = Coach(
                    name: coachName,
                    email: coachEmail.lowercased()
                )
                coach.athlete = athlete
                coach.invitationSentAt = Date()
                coach.lastInvitationStatus = "pending"
                modelContext.insert(coach)
                try modelContext.save()

                await MainActor.run {
                    isSending = false
                    Haptics.success()
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Failed to send invitation: \(error.localizedDescription)"
                    Haptics.error()
                }
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
                .foregroundColor(isOn ? .indigo : .gray)
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
