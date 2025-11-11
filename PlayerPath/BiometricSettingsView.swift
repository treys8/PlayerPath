//
//  BiometricSettingsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/10/25.
//

import SwiftUI

/// A view for managing biometric authentication settings
/// Can be integrated into a settings/profile screen
struct BiometricSettingsView: View {
    @StateObject private var biometricManager = BiometricAuthenticationManager()
    @State private var showingEnableSheet = false
    @State private var showingDisableConfirmation = false
    @State private var tempEmail = ""
    @State private var tempPassword = ""
    @State private var showPassword = false
    @State private var errorMessage: String?
    
    var body: some View {
        Section {
            if biometricManager.isBiometricAvailable {
                Toggle(isOn: $biometricManager.isBiometricEnabled) {
                    HStack {
                        Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(biometricManager.biometricTypeName) Sign In")
                                .font(.body)
                            Text("Sign in quickly using \(biometricManager.biometricTypeName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onChange(of: biometricManager.isBiometricEnabled) { oldValue, newValue in
                    if newValue && !oldValue {
                        // Enabling biometric
                        showingEnableSheet = true
                    } else if !newValue && oldValue {
                        // Disabling biometric
                        showingDisableConfirmation = true
                    }
                }
                
            } else {
                HStack {
                    Image(systemName: "faceid")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Biometric Authentication")
                            .font(.body)
                        Text("Not available on this device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("Security")
        } footer: {
            if biometricManager.isBiometricEnabled {
                Text("Your credentials are securely stored in the Keychain and can only be accessed with \(biometricManager.biometricTypeName).")
                    .font(.caption)
            }
        }
        .sheet(isPresented: $showingEnableSheet, onDismiss: {
            // If sheet dismissed without enabling, toggle back
            if !biometricManager.isBiometricEnabled {
                biometricManager.isBiometricEnabled = false
            }
        }) {
            EnableBiometricSheet(
                biometricManager: biometricManager,
                email: $tempEmail,
                password: $tempPassword,
                showPassword: $showPassword,
                errorMessage: $errorMessage,
                onEnable: {
                    showingEnableSheet = false
                },
                onCancel: {
                    biometricManager.isBiometricEnabled = false
                    showingEnableSheet = false
                }
            )
        }
        .alert("Disable \(biometricManager.biometricTypeName)?", isPresented: $showingDisableConfirmation) {
            Button("Cancel", role: .cancel) {
                biometricManager.isBiometricEnabled = true
            }
            Button("Disable", role: .destructive) {
                biometricManager.disableBiometric()
                HapticManager.shared.success()
            }
        } message: {
            Text("You'll need to sign in with your email and password next time.")
        }
    }
}

// MARK: - Enable Biometric Sheet

private struct EnableBiometricSheet: View {
    @ObservedObject var biometricManager: BiometricAuthenticationManager
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var errorMessage: String?
    
    let onEnable: () -> Void
    let onCancel: () -> Void
    
    @State private var isLoading = false
    @FocusState private var focusedField: EnableBiometricField?
    
    private enum EnableBiometricField {
        case email, password
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: biometricManager.biometricType == .faceID ? "faceid" : "touchid")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 20)
                    
                    // Header
                    VStack(spacing: 8) {
                        Text("Enable \(biometricManager.biometricTypeName)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Enter your credentials to securely enable \(biometricManager.biometricTypeName) for future sign-ins.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Credentials Form
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .disabled(isLoading)
                        
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textContentType(.password)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                            .disabled(isLoading)
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
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
                    
                    // Enable Button
                    Button(action: enableBiometric) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "Enabling..." : "Enable \(biometricManager.biometricTypeName)")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canEnable || isLoading)
                    .padding(.horizontal)
                    
                    // Security Notice
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Your credentials are securely encrypted and stored in the Keychain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.blue)
                            Text("Only accessible with \(biometricManager.biometricTypeName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isLoading)
                }
            }
            .onSubmit {
                if focusedField == .email {
                    focusedField = .password
                } else if canEnable {
                    enableBiometric()
                }
            }
            .onAppear {
                focusedField = .email
            }
        }
    }
    
    private var canEnable: Bool {
        !email.isEmpty && !password.isEmpty && FormValidator.shared.validateEmail(email).isValid
    }
    
    private func enableBiometric() {
        errorMessage = nil
        isLoading = true
        
        Task {
            let success = await biometricManager.enableBiometric(
                email: email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            
            await MainActor.run {
                isLoading = false
                
                if success {
                    HapticManager.shared.success()
                    onEnable()
                    
                    // Clear sensitive data
                    email = ""
                    password = ""
                } else {
                    errorMessage = "Failed to enable \(biometricManager.biometricTypeName). Please try again."
                    HapticManager.shared.error()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Form {
            BiometricSettingsView()
        }
        .navigationTitle("Settings")
    }
}
