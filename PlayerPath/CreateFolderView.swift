//
//  CreateFolderView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Form for athletes to create new shared folders and invite coaches
//

import SwiftUI

struct CreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var folderManager = SharedFolderManager.shared
    
    @State private var coachEmail = ""
    @State private var permissions = FolderPermissions.default

    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false

    private var isValid: Bool {
        !coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidEmail(coachEmail)
    }

    private var autoFolderName: String {
        let name = authManager.userDisplayName ?? authManager.userEmail ?? "Athlete"
        return "\(name)'s Videos"
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success!", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Folder created and invitation sent to \(coachEmail)")
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

            if !coachEmail.isEmpty && !isValidEmail(coachEmail) {
                Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

        } header: {
            Text("Invite Coach")
        } footer: {
            Text("Your coach will receive an invitation email to access this folder.")
                .font(.caption)
        }
    }

    private var permissionsSection: some View {
        Section {
            Toggle(isOn: $permissions.canUpload) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Upload Videos", systemImage: "arrow.up.circle.fill")
                    Text("Coach can add new videos to this folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle(isOn: $permissions.canComment) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Add Comments", systemImage: "text.bubble.fill")
                    Text("Coach can annotate and provide feedback on videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle(isOn: $permissions.canDelete) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Can Delete Videos", systemImage: "trash.fill")
                    Text("Coach can remove videos from this folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
        } header: {
            Text("Coach Permissions")
        } footer: {
            Text("You can change these permissions later.")
                .font(.caption)
        }
    }
    
    // MARK: - Actions
    
    private func createFolder() async {
        guard let athleteID = authManager.userID,
              let athleteName = authManager.userDisplayName ?? authManager.userEmail else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        
        isCreating = true
        
        do {
            let name = autoFolderName

            // Create folder
            let folderID = try await folderManager.createFolder(
                name: name,
                forAthlete: athleteID,
                hasCoachingAccess: authManager.hasCoachingAccess
            )

            // Invite coach
            try await folderManager.inviteCoachToFolder(
                coachEmail: coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                folderID: folderID,
                athleteID: athleteID,
                athleteName: athleteName,
                folderName: name,
                permissions: permissions
            )
            
            Haptics.success()
            showingSuccess = true
            
        } catch {
            errorMessage = "Failed to create folder. Please check your connection and try again."
            showingError = true
            Haptics.error()
        }

        isCreating = false
    }
    
    // MARK: - Validation
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Invite Coach View (for existing folders)

struct InviteCoachView: View {
    let folder: SharedFolder
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var folderManager = SharedFolderManager.shared
    
    @State private var coachEmail = ""
    @State private var permissions = FolderPermissions.default
    
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
    private var isValid: Bool {
        !coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidEmail(coachEmail)
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

                    if !coachEmail.isEmpty && !isValidEmail(coachEmail) {
                        Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                } header: {
                    Text("Coach Email")
                } footer: {
                    Text("Invite a coach to access \"\(folder.name)\"")
                        .font(.caption)
                }
                
                Section {
                    Toggle(isOn: $permissions.canUpload) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Upload Videos", systemImage: "arrow.up.circle.fill")
                            Text("Coach can add new videos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $permissions.canComment) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Add Comments", systemImage: "text.bubble.fill")
                            Text("Coach can annotate videos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $permissions.canDelete) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Can Delete Videos", systemImage: "trash.fill")
                            Text("Coach can remove videos")
                                .font(.caption)
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Invitation Sent!", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("\(coachEmail) will receive an invitation to access this folder.")
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
        
        isSending = true
        
        do {
            try await folderManager.inviteCoachToFolder(
                coachEmail: coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                folderID: folderID,
                athleteID: athleteID,
                athleteName: athleteName,
                folderName: folder.name,
                permissions: permissions
            )
            
            Haptics.success()
            showingSuccess = true
            
        } catch {
            errorMessage = "Failed to send invitation. Please check your connection and try again."
            showingError = true
            Haptics.error()
        }

        isSending = false
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Preview

#Preview("Create Folder") {
    CreateFolderView()
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
