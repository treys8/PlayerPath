//
//  PasswordResetView.swift
//  PlayerPath
//
//  Created by Assistant on 11/10/25.
//

import SwiftUI

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    @State private var email = ""
    @State private var emailSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                if !emailSent {
                    // Request Password Reset
                    VStack(spacing: 20) {
                        // Icon
                        Image(systemName: "key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .padding(.top, 20)
                        
                        // Header
                        VStack(spacing: 8) {
                            Text("Reset Password")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Enter your email address and we'll send you a link to reset your password.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Email Field
                        VStack(spacing: 12) {
                            TextField("Email Address", text: $email)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .focused($isEmailFocused)
                                .disabled(isLoading)
                                .padding(.horizontal)
                            
                            // Email validation feedback
                            if !email.isEmpty {
                                ValidationFeedbackView(
                                    result: FormValidator.shared.validateEmail(email)
                                )
                                .padding(.horizontal)
                            }
                        }
                        
                        // Error Message
                        if let errorMessage = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Send Button
                        Button(action: sendResetEmail) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(isLoading ? "Sending..." : "Send Reset Link")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!FormValidator.shared.validateEmail(email).isValid || isLoading)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    
                } else {
                    // Success State
                    VStack(spacing: 20) {
                        // Success Icon
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 40)
                        
                        // Success Message
                        VStack(spacing: 8) {
                            Text("Check Your Email")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("We've sent a password reset link to")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(email)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                            
                            Text("Check your inbox and follow the instructions to reset your password.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                        
                        // Instructions
                        VStack(alignment: .leading, spacing: 12) {
                            InstructionRow(
                                number: 1,
                                text: "Check your email inbox"
                            )
                            InstructionRow(
                                number: 2,
                                text: "Click the reset password link"
                            )
                            InstructionRow(
                                number: 3,
                                text: "Create a new password"
                            )
                            InstructionRow(
                                number: 4,
                                text: "Sign in with your new password"
                            )
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Done Button
                        Button(action: { dismiss() }) {
                            Text("Done")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                }
                
                Spacer()
                
                // Footer
                if !emailSent {
                    VStack(spacing: 8) {
                        Text("Didn't receive an email?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Text("Check your spam folder or")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("contact support") {
                                // Open email or support URL
                                if let url = URL(string: "mailto:support@playerpath.com") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption)
                        }
                    }
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
            .onAppear {
                isEmailFocused = true
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendResetEmail() {
        isLoading = true
        errorMessage = nil
        
        Task {
            await authManager.resetPassword(email: email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            
            await MainActor.run {
                isLoading = false
                
                if authManager.errorMessage != nil {
                    errorMessage = authManager.errorMessage
                    authManager.errorMessage = nil // Clear it so it doesn't show elsewhere
                    HapticManager.shared.error()
                } else {
                    emailSent = true
                    HapticManager.shared.success()
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    PasswordResetView()
        .environmentObject(ComprehensiveAuthManager())
}
