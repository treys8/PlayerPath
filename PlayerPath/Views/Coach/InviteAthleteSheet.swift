//
//  InviteAthleteSheet.swift
//  PlayerPath
//
//  Allows coaches to invite athletes by email
//

import SwiftUI
import FirebaseAuth

struct InviteAthleteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var athleteEmail = ""
    @State private var athleteName = ""
    @State private var personalMessage = ""
    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    private var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return athleteEmail.range(of: emailRegex, options: .regularExpression) != nil
    }

    private var canSend: Bool {
        isValidEmail && !athleteName.isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                        }

                        Text("Invite an Athlete")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Send an invitation to connect with an athlete's account")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Form
                    VStack(spacing: 16) {
                        // Athlete Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Athlete's Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("Enter athlete's name", text: $athleteName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                        }

                        // Parent/Guardian Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Parent/Guardian Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("parent@example.com", text: $athleteEmail)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()

                            if !athleteEmail.isEmpty && !isValidEmail {
                                Text("Please enter a valid email address")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // Personal Message (Optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personal Message (Optional)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("Add a note to the invitation...", text: $personalMessage, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)
                        }
                    }
                    .padding(.horizontal)

                    // Info box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)

                        Text("The athlete's parent will receive an email invitation. Once they accept, you'll be able to view their shared videos and send practice content.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
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
                        .background(canSend ? Color.green : Color.gray)
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
                Text("An invitation has been sent to \(athleteEmail). They'll receive an email with instructions to connect.")
            }
        }
    }

    private func sendInvitation() {
        guard canSend else { return }

        isSending = true
        errorMessage = nil

        Task {
            do {
                guard let coachID = authManager.userID,
                      let coachEmail = authManager.userEmail,
                      let coachName = authManager.currentFirebaseUser?.displayName ?? authManager.userEmail else {
                    throw InvitationError.missingCoachInfo
                }

                // Create invitation in Firestore
                try await FirestoreManager.shared.createCoachToAthleteInvitation(
                    coachID: coachID,
                    coachEmail: coachEmail,
                    coachName: coachName,
                    athleteEmail: athleteEmail.lowercased(),
                    athleteName: athleteName,
                    message: personalMessage.isEmpty ? nil : personalMessage
                )

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

enum InvitationError: LocalizedError {
    case missingCoachInfo

    var errorDescription: String? {
        switch self {
        case .missingCoachInfo:
            return "Could not retrieve your coach information. Please try signing out and back in."
        }
    }
}

#Preview {
    InviteAthleteSheet()
        .environmentObject(ComprehensiveAuthManager())
}
