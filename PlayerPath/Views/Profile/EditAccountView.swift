//
//  EditAccountView.swift
//  PlayerPath
//
//  Edit username, email, and profile picture.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct EditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var email: String
    let user: User
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showEmailVerificationAlert = false
    @State private var isSaving = false
    @FocusState private var usernameFocused: Bool
    @FocusState private var emailFocused: Bool

    init(user: User) {
        self.user = user
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
    }

    private var canSave: Bool {
        let usernameValid = username.trimmed.isNotEmpty
        let emailValid = email.trimmed.isValidEmail
        let hasChanges = username != user.username || email != user.email

        return usernameValid && emailValid && hasChanges && !isSaving
    }

    var body: some View {
        Form {
            Section("Profile Picture") {
                HStack {
                    Spacer()
                    EditableProfileImageView(user: user, size: .profileLarge) { _ in
                        do {
                            try modelContext.save()
                            Haptics.light()
                        } catch {
                            ErrorHandlerService.shared.handle(error, context: "ProfileView.saveProfileImage", showAlert: false)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Account Information") {
                TextField("Username", text: $username)
                    .focused($usernameFocused)
                    .submitLabel(.next)
                    .onSubmit { emailFocused = true }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Email", text: $email)
                    .focused($emailFocused)
                    .submitLabel(.done)
                    .onSubmit { emailFocused = false }
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                if !email.isEmpty && !email.isValidEmail {
                    Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.warning)
                }
            }

            Section {
                Button {
                    Task {
                        await save()
                    }
                } label: {
                    LoadingButtonContent(text: "Save Changes", isLoading: isSaving)
                }
                .disabled(!canSave)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text(saveErrorMessage.isEmpty ? ProfileStrings.pleaseRetry : saveErrorMessage)
        }
        .alert("Verify Your Email", isPresented: $showEmailVerificationAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("A verification link was sent to \(email.trimmed). Click it to confirm your new email address.")
        }
    }

    private func save() async {
        let trimmedUsername = username.trimmed
        let trimmedEmail = email.trimmed

        // Validate
        let usernameValidation = trimmedUsername.validateUsername()
        guard usernameValidation.isValid else {
            ErrorHandlerService.shared.reportWarning(usernameValidation.message, context: "ProfileView.validateUsername", message: $saveErrorMessage, isPresented: $showSaveError)
            return
        }

        let emailValidation = trimmedEmail.validateEmail()
        guard emailValidation.isValid else {
            ErrorHandlerService.shared.reportWarning(emailValidation.message, context: "ProfileView.validateEmail", message: $saveErrorMessage, isPresented: $showSaveError)
            return
        }

        isSaving = true
        defer { isSaving = false }

        let emailChanged = trimmedEmail != user.email

        // Update Firebase Auth email if changed
        if emailChanged, let firebaseUser = Auth.auth().currentUser {
            do {
                try await firebaseUser.sendEmailVerification(beforeUpdatingEmail: trimmedEmail)
            } catch AuthErrorCode.requiresRecentLogin {
                ErrorHandlerService.shared.reportWarning("For security, please sign out and sign back in before changing your email.", context: "ProfileView.updateEmail.recentLogin", message: $saveErrorMessage, isPresented: $showSaveError)
                return
            } catch AuthErrorCode.emailAlreadyInUse {
                ErrorHandlerService.shared.reportWarning("That email address is already associated with another account.", context: "ProfileView.updateEmail.alreadyInUse", message: $saveErrorMessage, isPresented: $showSaveError)
                return
            } catch {
                ErrorHandlerService.shared.reportError(error, context: "ProfileView.updateEmail", message: $saveErrorMessage, isPresented: $showSaveError, userMessage: "Unable to update email: \(error.localizedDescription)")
                return
            }
        }

        user.username = trimmedUsername
        // Don't update user.email locally until the verification link is clicked and
        // Firebase Auth reflects the change. loadUserProfile() syncs email on next sign-in.
        if !emailChanged {
            user.email = trimmedEmail
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000) // Brief delay for UX
            try modelContext.save()
            Haptics.success()
            if emailChanged {
                showEmailVerificationAlert = true
            } else {
                dismiss()
            }
        } catch {
            ErrorHandlerService.shared.reportError(error, context: "ProfileView.saveProfile", message: $saveErrorMessage, isPresented: $showSaveError, userMessage: String(format: ProfileStrings.saveFailed, error.localizedDescription))
        }
    }
}
