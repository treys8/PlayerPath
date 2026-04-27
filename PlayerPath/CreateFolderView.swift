//
//  CreateFolderView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Form for athletes to create new shared folders and invite coaches
//

import SwiftUI

struct CreateFolderView: View {
    let athlete: Athlete

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var folderManager: SharedFolderManager { .shared }

    @State private var coachEmail = ""
    @State private var permissions = FolderPermissions.default

    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false

    private var isValid: Bool {
        !coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        coachEmail.isValidEmail
    }

    private var autoFolderName: String {
        "\(athlete.name)'s Videos"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                coachInviteSection
                permissionsSection
                
                if isCreating {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                            Spacer()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Shared Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createFolder()
                        }
                    }
                    .disabled(!isValid || isCreating)
                }
            }
            .alert("Unable to Create Folder", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .toast(isPresenting: $showingSuccess, message: "Folder Created")
            .onChange(of: showingSuccess) { _, new in
                if !new { dismiss() }
            }
        }
    }
    
    // MARK: - Form Sections

    private var coachInviteSection: some View {
        Section {
            TextField("Coach's Email", text: $coachEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    guard isValid else { return }
                    Task { await createFolder() }
                }

            if !coachEmail.isEmpty && !coachEmail.isValidEmail {
                Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                    .font(.bodySmall)
                    .foregroundColor(.orange)
            }

        } header: {
            Text("Invite Coach")
        } footer: {
            Text("Your coach will receive an invitation email to access this folder.")
                .font(.bodySmall)
        }
    }

    private var permissionsSection: some View {
        Section {
            Toggle(isOn: $permissions.canUpload) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Upload Videos", systemImage: "arrow.up.circle.fill")
                    Text("Coach can add new videos to this folder")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle(isOn: $permissions.canComment) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Add Comments", systemImage: "text.bubble.fill")
                    Text("Coach can annotate and provide feedback on videos")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle(isOn: $permissions.canDelete) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Delete Videos", systemImage: "trash.fill")
                    Text("Coach can remove videos from this folder")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
        } header: {
            Text("Coach Permissions")
        } footer: {
            Text("You can change these permissions later.")
                .font(.bodySmall)
        }
    }
    
    // MARK: - Actions
    
    private func createFolder() async {
        guard let userID = authManager.userID else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        let athleteUUID = athlete.id.uuidString
        let athleteName = athlete.name

        isCreating = true

        do {
            let name = autoFolderName

            // Create folder
            let folderID = try await folderManager.createFolder(
                name: name,
                forAthlete: userID,
                athleteName: athleteName,
                athleteUUID: athleteUUID,
                hasCoachingAccess: authManager.hasCoachingAccess
            )

            // Invite coach
            try await folderManager.inviteCoachToFolder(
                coachEmail: coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                folderID: folderID,
                athleteID: userID,
                athleteName: athleteName,
                athleteUUID: athleteUUID,
                folderName: name,
                permissions: permissions
            )
            
            Haptics.success()
            showingSuccess = true
            
        } catch {
            errorMessage = "Failed to create folder. Please check your connection and try again."
            showingError = true
            ErrorHandlerService.shared.handle(error, context: "CreateFolderView.createFolder", showAlert: false)
        }

        isCreating = false
    }
    
}

// MARK: - Invite Coach View (for existing folders)

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
                            .foregroundColor(.orange)
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
                folderName: folder.name,
                permissions: permissions
            )
            
            Haptics.success()
            showingSuccess = true
            
        } catch {
            errorMessage = "Failed to send invitation. Please check your connection and try again."
            showingError = true
            ErrorHandlerService.shared.handle(error, context: "CreateFolderView.sendInvitation", showAlert: false)
        }

        isSending = false
    }
    
}

// MARK: - Preview

#Preview("Create Folder") {
    CreateFolderView(athlete: Athlete(name: "Preview Athlete"))
        .environmentObject(ComprehensiveAuthManager())
}

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
