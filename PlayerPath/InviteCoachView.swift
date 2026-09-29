//
//  InviteCoachView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Invite a coach to an existing shared folder. New coach connections go
//  through InviteCoachSheet (folder is created server-side on accept).
//

import SwiftUI

struct InviteCoachView: View {
    let folder: SharedFolder
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var folderManager: SharedFolderManager { .shared }
    
    @State private var coachEmail = ""
    @State private var permissions = FolderPermissions.default
    
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
    private var isValid: Bool {
        !coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        coachEmail.isValidEmail
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Coach's Email", text: $coachEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            guard isValid else { return }
                            Task { await sendInvitation() }
                        }

                    if !coachEmail.isEmpty && !coachEmail.isValidEmail {
                        Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                    }

                } header: {
                    Text("Coach Email")
                } footer: {
                    Text("Invite a coach to access \"\(folder.name)\"")
                        .font(.bodySmall)
                }
                
                Section {
                    Toggle(isOn: $permissions.canUpload) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Upload Videos", systemImage: "arrow.up.circle.fill")
                            Text("Coach can add new videos")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $permissions.canComment) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Add Comments", systemImage: "text.bubble.fill")
                            Text("Coach can annotate videos")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $permissions.canDelete) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Delete Videos", systemImage: "trash.fill")
                            Text("Coach can remove videos")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Permissions")
                }
                
                if isSending {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Invite Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Invitation") {
                        Task {
                            await sendInvitation()
                        }
                    }
                    .disabled(!isValid || isSending)
                }
            }
            .alert("Unable to Send Invitation", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .toast(isPresenting: $showingSuccess, message: "Invitation Sent")
            .onChange(of: showingSuccess) { _, new in
                if !new { dismiss() }
            }
        }
    }
    
    private func sendInvitation() async {
        guard let folderID = folder.id,
              let athleteID = authManager.userID,
              let athleteName = authManager.userDisplayName ?? authManager.userEmail else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        guard let athleteUUID = folder.athleteUUID else {
            errorMessage = "This folder is from an older version. Re-create it to invite a coach."
            showingError = true
            return
        }

        isSending = true

        do {
            try await folderManager.inviteCoachToFolder(
                coachEmail: coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                folderID: folderID,
                athleteID: athleteID,
                athleteName: athleteName,
                athleteUUID: athleteUUID,
                personGroupID: folder.personGroupID ?? athleteUUID,
                folderName: folder.name,
                permissions: permissions
            )
            
            Haptics.success()
            showingSuccess = true
            
        } catch {
            errorMessage = "Failed to send invitation. Please check your connection and try again."
            showingError = true
            ErrorHandlerService.shared.handle(error, context: "InviteCoachView.sendInvitation", showAlert: false)
        }

        isSending = false
    }
    
}

// MARK: - Preview

#Preview("Invite Coach") {
    InviteCoachView(
        folder: SharedFolder(
            id: "preview",
            name: "Coach Smith",
            ownerAthleteID: "athlete123",
            ownerAthleteName: "Test Athlete",
            sharedWithCoachIDs: [],
            permissions: [:],
            createdAt: Date(),
            updatedAt: Date(),
            videoCount: 0
        )
    )
    .environmentObject(ComprehensiveAuthManager())
}
