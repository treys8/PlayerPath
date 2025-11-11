//
//  SignInView.swift
//  PlayerPath
//
//  User authentication interface
//

import SwiftUI

struct SignInView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isCreatingAccount = false
    @State private var showingAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // App Logo/Title
                VStack(spacing: 15) {
                    Image(systemName: "figure.baseball")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("PlayerPath")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Track your baseball journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 20) {
                    // Google Sign In Button (Temporarily disabled)
                    /*
                    Button(action: {
                        Task {
                            await authManager.signInWithGoogle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "globe")
                                .font(.title3)
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .disabled(authManager.isLoading)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                        Text("or")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                    }
                    */
                    
                    // Email/Password Form
                    VStack(spacing: 15) {
                        if isCreatingAccount {
                            TextField("Full Name", text: $displayName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            Task {
                                if isCreatingAccount {
                                    await authManager.createAccount(
                                        email: email,
                                        password: password,
                                        displayName: displayName
                                    )
                                } else {
                                    await authManager.signInWithEmail(email, password: password)
                                }
                            }
                        }) {
                            Text(isCreatingAccount ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .disabled(authManager.isLoading || email.isEmpty || password.isEmpty || (isCreatingAccount && displayName.isEmpty))
                        
                        Button(action: {
                            isCreatingAccount.toggle()
                        }) {
                            Text(isCreatingAccount ? "Already have an account? Sign In" : "Don't have an account? Create One")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Try without account option
                    VStack(spacing: 10) {
                        Text("Want to try the app first?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            Task {
                                await authManager.signInAnonymously()
                            }
                        }) {
                            Text("Continue without account")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        
                        Text("(Videos won't sync across devices)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if authManager.isLoading {
                    ProgressView("Signing in...")
                }
            }
            .padding()
            .navigationBarHidden(true)
            .alert("Sign In Error", isPresented: .constant(!authManager.errorMessage.isEmpty)) {
                Button("OK") {
                    authManager.errorMessage = ""
                }
            } message: {
                Text(authManager.errorMessage)
            }
        }
    }
}

#Preview {
    SignInView()
}