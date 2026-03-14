//
//  AppleSignInManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/10/25.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth
import CryptoKit
import Combine

@MainActor
final class AppleSignInManager: NSObject, ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentNonce: String?
    private var nonceTimestamp: Date?
    private let nonceExpirationSeconds: TimeInterval = 300 // 5 minutes
    private var authManager: ComprehensiveAuthManager?
    private var reAuthNonce: String?
    private var reAuthContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var reAuthController: ASAuthorizationController?

    /// Role to apply when a new user signs up via Apple ID.
    /// Set this before calling signInWithApple() based on the user's role selection.
    var pendingRole: UserRole = .athlete

    func configure(with authManager: ComprehensiveAuthManager) {
        self.authManager = authManager
    }

    func cleanup() {
        self.authManager = nil
    }

    // MARK: - Sign in with Apple
    
    func signInWithApple() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Generate nonce and timestamp for security
        let nonce = randomNonceString()
        currentNonce = nonce
        nonceTimestamp = Date()

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - Re-authentication

    func reauthenticate() async throws -> OAuthCredential {
        let nonce = randomNonceString()
        reAuthNonce = nonce
        let appleCredential: ASAuthorizationAppleIDCredential = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reAuthContinuation = continuation
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = []
                request.nonce = sha256(nonce)
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                reAuthController = controller // Retain strongly so it isn't deallocated before the delegate fires
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor in
                if let continuation = self.reAuthContinuation {
                    self.reAuthContinuation = nil
                    self.reAuthNonce = nil
                    self.reAuthController = nil
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
        guard let idToken = appleCredential.identityToken,
              let idTokenString = String(data: idToken, encoding: .utf8),
              let rawNonce = reAuthNonce else {
            throw NSError(domain: "AppleSignInManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Apple re-auth credential invalid"])
        }
        reAuthNonce = nil
        return OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: rawNonce, fullName: nil)
    }

    // MARK: - Helper Methods
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fallback to UUID-based nonce if SecRandom fails
            print("⚠️ SecRandomCopyBytes failed with \(errorCode), using UUID fallback")
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length).lowercased()
        }
        
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    /// Sign in with Firebase with automatic retry for transient network errors
    private func signInWithRetry(credential: AuthCredential, attempt: Int = 1, maxAttempts: Int = 3) async throws -> AuthDataResult {
        do {
            return try await Auth.auth().signIn(with: credential)
        } catch {
            let nsError = error as NSError
            
            // Retry only on transient network errors
            let retryableErrors: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet
            ]
            
            if retryableErrors.contains(nsError.code) && attempt < maxAttempts {
                let delay = pow(2.0, Double(attempt)) // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                print("⚠️ Retrying Firebase sign in (attempt \(attempt + 1)/\(maxAttempts))")
                return try await signInWithRetry(credential: credential, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
            
            throw error
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task {
            // Handle re-auth continuation before normal sign-in flow
            if let continuation = reAuthContinuation {
                reAuthContinuation = nil
                reAuthController = nil
                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    continuation.resume(throwing: NSError(domain: "AppleSignInManager", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"]))
                    isLoading = false
                    return
                }
                continuation.resume(returning: appleIDCredential)
                isLoading = false
                return
            }

            do {
                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    await MainActor.run {
                        errorMessage = "Invalid Apple ID credential"
                        isLoading = false
                    }
                    return
                }
                
                guard let nonce = currentNonce else {
                    await MainActor.run {
                        errorMessage = "Invalid state: A login callback was received, but no login request was sent."
                        isLoading = false
                    }
                    return
                }

                // Validate nonce expiration for security
                if let timestamp = nonceTimestamp {
                    let elapsed = Date().timeIntervalSince(timestamp)
                    if elapsed > nonceExpirationSeconds {
                        await MainActor.run {
                            errorMessage = "Sign in request expired. Please try again."
                            isLoading = false
                            currentNonce = nil
                            nonceTimestamp = nil
                        }
                        print("🔴 Apple Sign In nonce expired after \(elapsed) seconds")
                        return
                    }
                }
                
                guard let appleIDToken = appleIDCredential.identityToken else {
                    await MainActor.run {
                        errorMessage = "Unable to fetch identity token"
                        isLoading = false
                    }
                    return
                }
                
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    await MainActor.run {
                        errorMessage = "Unable to serialize token string from data"
                        isLoading = false
                    }
                    return
                }
                
                // Create Firebase credential
                let credential = OAuthProvider.appleCredential(
                    withIDToken: idTokenString,
                    rawNonce: nonce,
                    fullName: appleIDCredential.fullName
                )
                
                // Sign in with Firebase (with automatic retry for transient errors)
                let result = try await signInWithRetry(credential: credential)

                // Check if this is a new user
                let isNewUser = result.additionalUserInfo?.isNewUser ?? false

                // IMPORTANT: Update auth state BEFORE commitChanges() to prevent a race
                // condition where the Firebase auth state listener fires during the
                // commitChanges() await and sees isNewUser = false, incorrectly calling
                // loadUserProfile() and overwriting the coach role with .athlete.
                await MainActor.run {
                    authManager?.updateCurrentUser(result.user, isNewUser: isNewUser, role: isNewUser ? pendingRole : nil)
                }

                // Update display name if available and not already set
                if let fullName = appleIDCredential.fullName,
                   result.user.displayName == nil || result.user.displayName?.isEmpty == true {
                    let displayName = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")

                    if !displayName.isEmpty {
                        let changeRequest = result.user.createProfileChangeRequest()
                        changeRequest.displayName = displayName
                        try await changeRequest.commitChanges()
                    }
                }

                await MainActor.run {
                    isLoading = false
                    currentNonce = nil // Clear nonce after successful use
                    nonceTimestamp = nil
                    print("🟢 Apple Sign In successful for: \(result.user.email ?? "unknown")")
                    HapticManager.shared.authenticationSuccess()
                }
                
            } catch {
                await MainActor.run {
                    currentNonce = nil // Clear nonce on error too
                    nonceTimestamp = nil
                    errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
                    isLoading = false
                    print("🔴 Apple Sign In error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            if let continuation = reAuthContinuation {
                reAuthContinuation = nil
                reAuthNonce = nil
                reAuthController = nil
                continuation.resume(throwing: error)
                isLoading = false
                return
            }

            currentNonce = nil // Clear nonce on cancellation/error
            nonceTimestamp = nil
            let authError = error as NSError

            // Don't show error if user cancelled
            if authError.code == ASAuthorizationError.canceled.rawValue {
                print("User cancelled Apple Sign In")
            } else {
                errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
                print("🔴 Apple Sign In error: \(error.localizedDescription)")
            }

            isLoading = false
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Try active foreground scene first
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }

        // Fallback to any scene with a window
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first {
                return window
            }
        }

        // Last resort: create a window with the first available window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: windowScene)
        }

        // Unreachable on any real device — every iOS 15+ app has at least one UIWindowScene.
        fatalError("No UIWindowScene available for Apple Sign In presentation")
    }
}

// MARK: - SwiftUI Button Wrapper

struct SignInWithAppleButton: View {
    let isSignUp: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                
                Text("Sign \(isSignUp ? "up" : "in") with Apple")
                    .font(.system(size: 17, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .background(colorScheme == .dark ? Color.white : Color.black)
            .cornerRadius(10)
        }
        .accessibilityLabel("Sign \(isSignUp ? "up" : "in") with Apple")
        .accessibilityHint("Use your Apple ID to sign \(isSignUp ? "up" : "in")")
    }
}

