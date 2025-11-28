//
//  MainAppView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//
//  CRITICAL FIXES APPLIED:
//  1. ✅ NotificationCenter Memory Leak Prevention - Using @StateObject NotificationObserverManager for lifecycle safety
//  2. ✅ SwiftData Relationship Race Condition - Set relationships before insert, let inverse handle array
//  3. ✅ Safe Predicate Implementation - Removed force unwrap, using Swift filter instead
//  4. ✅ Task Cancellation - All async tasks check for cancellation and store references for cleanup
//  5. ✅ Observer Duplication Prevention - Dedicated ObservableObject manages observers with automatic cleanup
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

extension View {
    /// Lightweight glass effect wrapper fallback when glassEffect is not available everywhere
    func appGlass(cornerRadius: CGFloat = 12, overlayOpacity: Double = 0.1) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(overlayOpacity))
                            .blendMode(.overlay)
                    )
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

/// App-wide notifications used for cross-feature coordination.
/// - switchTab: Pass an Int tab index as object to switch the main TabView.
/// - presentVideoRecorder: Ask Videos module to present its recorder UI.
/// - showAthleteSelection: Request athlete selection UI to be shown.
/// - recordedHitResult: Post with object ["hitType": String] to update highlights and stats.


// MARK: - Main Tab Enum
enum MainTab: Int {
    case home = 0
    case tournaments = 1
    case games = 2
    case stats = 3
    case practice = 4
    case videos = 5
    case highlights = 6
    case profile = 7
}

// Convenience helper to switch tabs via NotificationCenter
@inline(__always)
func postSwitchTab(_ tab: MainTab) {
    NotificationCenter.default.post(name: .switchTab, object: tab.rawValue)
}

// MARK: - App-wide Notifications
// Notification names are now defined in AppNotifications.swift

// MARK: - NotificationObserverManager

/// Manages NotificationCenter observers with automatic lifecycle handling
/// This prevents observer duplication during view lifecycle events
final class NotificationObserverManager: ObservableObject {
    private var observers: [NSObjectProtocol] = []
    
    deinit {
        // Cleanup synchronously in deinit - this is safe because
        // removeObserver is synchronous and doesn't require MainActor
        // Remove observers directly here since deinit is non-isolated
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
    
    /// Add an observer and track it for cleanup
    @MainActor
    func observe(name: Notification.Name, object: Any? = nil, using block: @escaping @Sendable (Notification) -> Void) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main,
            using: block
        )
        observers.append(observer)
    }
    
    /// Remove all observers
    @MainActor
    func cleanup() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}



// MARK: - Helper Views

struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            
            Spacer(minLength: 0)
        }
    }
}


// Inserted placeholder views for missing types here:

// MARK: - App Root Helper Views

struct ErrorView: View {
    let message: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(.title3).bold()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct FirstAthleteCreationView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    let authManager: ComprehensiveAuthManager
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                Text("Create Your First Athlete")
                    .font(.title2).bold()
                Text("Tap the + button to add your first athlete from the selection screen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    // Fallback: present the add athlete sheet by posting selection request
                    NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                } label: {
                    Label("Add Athlete", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Main App Root
struct PlayerPathMainView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                AuthenticatedFlow()
            } else {
                WelcomeFlow()
            }
        }
        .environmentObject(authManager)
        .tint(.blue)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    }
}

// MARK: - Welcome Flow
struct WelcomeFlow: View {
    private enum AuthSheet: Identifiable {
        case signIn
        case signUp
        var id: String { self == .signIn ? "signIn" : "signUp" }
    }
    
    @State private var activeSheet: AuthSheet? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // App Logo and Branding
                VStack(spacing: 24) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    VStack(spacing: 12) {
                        Text("PlayerPath")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text("Your Baseball Journey Starts Here")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Feature highlights
                VStack(alignment: .leading, spacing: 16) {
                    Text("Track Your Performance")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    
                    FeatureHighlight(
                        icon: "video.circle.fill",
                        title: "Record & Analyze",
                        description: "Capture practice sessions and games with smart analysis"
                    )
                    
                    FeatureHighlight(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        title: "Track Statistics",
                        description: "Monitor batting averages and performance metrics"
                    )
                    
                    FeatureHighlight(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Sync Everywhere",
                        description: "Your data syncs securely across all devices"
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: { activeSheet = .signUp }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.headline)
                            Text("Get Started")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Sign up to get started")
                    .accessibilityHint("Creates a new account and begins onboarding")
                    .accessibilityIdentifier("welcome_get_started")
                    .accessibilitySortPriority(1)
                    
                    Button(action: { activeSheet = .signIn }) {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .font(.headline)
                            Text("Sign In")
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.clear)
                        .foregroundColor(.blue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    }
                    .accessibilityLabel("Sign in to existing account")
                    .accessibilityHint("Sign in with your existing credentials")
                    .accessibilityIdentifier("welcome_sign_in")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .signIn:
                ComprehensiveSignInView(isSignUpMode: false)
            case .signUp:
                ComprehensiveSignInView(isSignUpMode: true)
            }
        }
    }
}



// MARK: - ComprehensiveSignInView
struct ComprehensiveSignInView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    
    let isSignUpMode: Bool
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showingForgotPassword = false
    @State private var showingResetPasswordSheet = false
    @State private var selectedRole: UserRole = .athlete
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Text(isSignUpMode ? "Create Account" : "Sign In")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(isSignUpMode ? (selectedRole == .athlete ? "Join PlayerPath to track your baseball journey" : "Join PlayerPath to coach your athletes") : "Welcome back to PlayerPath")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Role Selection (Sign Up only)
                if isSignUpMode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("I am a:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            RoleSelectionButton(
                                role: .athlete,
                                isSelected: selectedRole == .athlete,
                                icon: "figure.baseball",
                                title: "Athlete",
                                description: "Track my progress"
                            ) {
                                Haptics.light()
                                selectedRole = .athlete
                            }
                            
                            RoleSelectionButton(
                                role: .coach,
                                isSelected: selectedRole == .coach,
                                icon: "person.2.fill",
                                title: "Coach",
                                description: "Work with athletes"
                            ) {
                                Haptics.light()
                                selectedRole = .coach
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                VStack(spacing: 20) {
                    if isSignUpMode {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .accessibilityLabel("Display name")
                            .accessibilityHint("Enter your preferred display name")
                        
                        // Display name validation
                        if !displayName.isEmpty {
                            HStack {
                                Image(systemName: isValidDisplayName(displayName) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isValidDisplayName(displayName) ? .green : .orange)
                                    .font(.caption)
                                Text(getDisplayNameValidationMessage(displayName))
                                    .font(.caption2)
                                    .foregroundColor(isValidDisplayName(displayName) ? .green : .orange)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Email address")
                        .accessibilityHint("Enter your email address")
                        .onSubmit {
                            if canSubmitForm() && !authManager.isLoading {
                                performAuth()
                            }
                        }
                        .submitLabel(isSignUpMode ? .next : .go)
                    
                    // Email validation feedback
                    if !email.isEmpty {
                        HStack {
                            Image(systemName: isValidEmail(email) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isValidEmail(email) ? .green : .orange)
                                .font(.caption)
                            Text(isValidEmail(email) ? "Valid email format" : "Please enter a valid email address")
                                .font(.caption2)
                                .foregroundColor(isValidEmail(email) ? .green : .orange)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.asciiCapable)
                        .accessibilityLabel("Password")
                        .accessibilityHint("Enter your password")
                        .onSubmit {
                            if canSubmitForm() && !authManager.isLoading {
                                performAuth()
                            }
                        }
                        .submitLabel(.go)
                    
                    // Password validation feedback
                    if !password.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: isValidPassword(password) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isValidPassword(password) ? .green : .orange)
                                    .font(.caption)
                                Text(isValidPassword(password) ? "Strong password" : "Password requirements:")
                                    .font(.caption2)
                                    .foregroundColor(isValidPassword(password) ? .green : .orange)
                                Spacer()
                            }
                            
                            if !isValidPassword(password) && isSignUpMode {
                                VStack(alignment: .leading, spacing: 2) {
                                    ValidationRequirement(
                                        text: "At least 8 characters",
                                        isMet: password.count >= 8
                                    )
                                    ValidationRequirement(
                                        text: "Contains uppercase letter",
                                        isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
                                    )
                                    ValidationRequirement(
                                        text: "Contains lowercase letter",
                                        isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
                                    )
                                    ValidationRequirement(
                                        text: "Contains number",
                                        isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Form validation summary
                if !email.isEmpty || !password.isEmpty || (isSignUpMode && !displayName.isEmpty) {
                    HStack {
                        Image(systemName: canSubmitForm() ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundColor(canSubmitForm() ? .green : .blue)
                            .font(.caption)
                        
                        Text(getFormValidationSummary())
                            .font(.caption2)
                            .foregroundColor(canSubmitForm() ? .green : .blue)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                VStack(spacing: 15) {
                    Button(action: { Haptics.light(); performAuth() }) {
                        HStack {
                            if authManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(authManager.isLoading ? (isSignUpMode ? "Creating Account..." : "Signing In...") : (isSignUpMode ? "Create Account" : "Sign In"))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmitForm() || authManager.isLoading)
                    
                    if !isSignUpMode {
                        Button("Forgot Password?") {
                            showingResetPasswordSheet = true
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                if let errorMessage = authManager.errorMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("Authentication Error")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            Spacer()
                            
                            Button("Dismiss") {
                                authManager.clearError()
                            }
                            .font(.caption2)
                            .foregroundColor(.red)
                        }
                        
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(isSignUpMode ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingResetPasswordSheet) {
            ResetPasswordSheet(email: $email)
        }
        // Auto-dismiss on successful authentication
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                Task { @MainActor in
                    dismiss()
                }
            }
        }
    }
    
    private func performAuth() {
        Task {
            let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !Task.isCancelled else { return }
            
            #if DEBUG
            print("🔵 Attempting authentication:")
            print("  - Email: \(normalizedEmail.isEmpty ? "EMPTY" : "***@***")")
            print("  - Password length: \(password.count)")
            print("  - Is sign up: \(isSignUpMode)")
            print("  - Role: \(selectedRole.rawValue)")
            #endif
            
            if isSignUpMode {
                if selectedRole == .coach {
                    await authManager.signUpAsCoach(
                        email: normalizedEmail,
                        password: password,
                        displayName: trimmedDisplayName.isEmpty ? "Coach" : trimmedDisplayName
                    )
                } else {
                    await authManager.signUp(
                        email: normalizedEmail,
                        password: password,
                        displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                    )
                }
            } else {
                await authManager.signIn(email: normalizedEmail, password: password)
            }
            
            guard !Task.isCancelled else { return }
            
            // Add haptic feedback on successful authentication
            if authManager.isSignedIn {
                await MainActor.run {
                    Haptics.light()
                }
            }
        }
    }
    
    // MARK: - Validation Functions
    
    private func isValidEmail(_ email: String) -> Bool {
        Validation.isValidEmail(email)
    }
    
    private func isValidPassword(_ password: String) -> Bool {
        if isSignUpMode {
            return password.count >= 8 &&
                   password.range(of: "[A-Z]", options: .regularExpression) != nil &&
                   password.range(of: "[a-z]", options: .regularExpression) != nil &&
                   password.range(of: "[0-9]", options: .regularExpression) != nil
        } else {
            return !password.isEmpty
        }
    }
    
    private func isValidDisplayName(_ name: String) -> Bool {
        Validation.isValidPersonName(name, min: 2, max: 30)
    }
    
    private func getDisplayNameValidationMessage(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return "Name cannot be empty"
        } else if trimmedName.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmedName.count > 30 {
            return "Name must be 30 characters or less"
        } else if Validation.isValidPersonName(trimmedName, min: 2, max: 30) {
            return "Valid display name"
        } else {
            return "Name can only contain letters, spaces, periods, hyphens, and apostrophes"
        }
    }
    
    private func canSubmitForm() -> Bool {
        let emailValid = isValidEmail(email)
        let passwordValid = isValidPassword(password)
        let displayNameValid = isSignUpMode ? (displayName.isEmpty || isValidDisplayName(displayName)) : true
        
        return emailValid && passwordValid && displayNameValid
    }
    
    private func getFormValidationSummary() -> String {
        var requirements: [(String, Bool)] = [
            ("Valid email", isValidEmail(email)),
            ("Valid password", isValidPassword(password))
        ]
        
        if isSignUpMode {
            requirements.append(("Valid display name", displayName.isEmpty || isValidDisplayName(displayName)))
        }
        
        let metCount = requirements.filter { $0.1 }.count
        let totalCount = requirements.count
        
        if metCount == totalCount {
            return "Ready to \(isSignUpMode ? "create account" : "sign in")!"
        } else {
            return "\(metCount) of \(totalCount) requirements met"
        }
    }
}

// MARK: - TrialStatusView
struct TrialStatusView: View {
    let authManager: ComprehensiveAuthManager
    @State private var showingUpgrade = false
    
    var body: some View {
        if !authManager.isPremiumUser {
            HStack(spacing: 12) {
                statusIcon
                statusText
                Spacer()
                upgradeButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(statusBackgroundColor)
            .cornerRadius(12)
            .animation(.easeInOut(duration: 0.3), value: authManager.trialDaysRemaining)
        }
    }
    
    private var statusIcon: some View {
        Image(systemName: authManager.trialDaysRemaining > 0 ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill")
            .foregroundColor(authManager.trialDaysRemaining > 0 ? .orange : .red)
            .font(.title3)
    }
    
    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            if authManager.trialDaysRemaining > 0 {
                Text("Free Trial")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("\(authManager.trialDaysRemaining) days remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
            } else {
                Text("Trial Expired")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                
                Text("Upgrade to continue using all features")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var upgradeButton: some View {
        Button(action: { Haptics.light(); showingUpgrade = true }) {
            Text("Upgrade")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .sheet(isPresented: $showingUpgrade) {
            // TODO: Create a proper premium upgrade view
            NavigationStack {
                VStack {
                    Text("Premium Features")
                        .font(.title)
                    Text("Coming Soon...")
                        .foregroundColor(.secondary)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingUpgrade = false
                        }
                    }
                }
            }
        }
    }
    
    private var statusBackgroundColor: Color {
        authManager.trialDaysRemaining > 0
            ? Color.orange.opacity(0.1)
            : Color.red.opacity(0.1)
    }
}

// MARK: - Reset Password Sheet

struct ResetPasswordSheet: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String
    
    @State private var resetEmail = ""
    @State private var isLoading = false
    @State private var showingSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 32)
                
                VStack(spacing: 12) {
                    Text("Reset Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    TextField("Email", text: $resetEmail)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(.horizontal)
                    
                    Button {
                        sendResetEmail()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "Sending..." : "Send Reset Link")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(resetEmail.isEmpty || isLoading)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                resetEmail = email
            }
            .alert("Email Sent", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Check your email for a password reset link.")
            }
        }
    }
    
    private func sendResetEmail() {
        isLoading = true
        Task {
            await authManager.resetPassword(email: resetEmail)
            await MainActor.run {
                isLoading = false
                showingSuccess = true
            }
        }
    }
}

// MARK: - Onboarding Flow
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @State private var selectedAthlete: Athlete?
    
    var body: some View {
        // Show different onboarding based on user role
        Group {
            if authManager.userRole == .coach {
                CoachOnboardingFlow(
                    modelContext: modelContext,
                    authManager: authManager,
                    user: user
                )
            } else {
                AthleteOnboardingFlow(
                    modelContext: modelContext,
                    authManager: authManager,
                    user: user
                )
            }
        }
        .onAppear {
            print("🎯 OnboardingFlow - User role: \(authManager.userRole.rawValue)")
            print("🎯 OnboardingFlow - User email: \(user.email)")
            print("🎯 OnboardingFlow - Showing \(authManager.userRole == .coach ? "COACH" : "ATHLETE") onboarding")
            print("🎯 OnboardingFlow - isNewUser: \(authManager.isNewUser)")
            print("🎯 OnboardingFlow - isSignedIn: \(authManager.isSignedIn)")
            
            // Extra debugging
            if let profile = authManager.userProfile {
                print("🎯 OnboardingFlow - Profile role: \(profile.userRole.rawValue)")
                print("🎯 OnboardingFlow - Profile email: \(profile.email)")
            } else {
                print("⚠️ OnboardingFlow - NO PROFILE LOADED (this is expected for new users)")
                print("⚠️ OnboardingFlow - Using local userRole value: \(authManager.userRole.rawValue)")
            }
        }
    }
}

// MARK: - Athlete Onboarding Flow
struct AthleteOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // ATHLETE BADGE - Makes it obvious this is the athlete flow
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "figure.baseball")
                            .font(.caption)
                        Text("ATHLETE ACCOUNT")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.2))
                    )
                    .foregroundColor(.blue)
                    Spacer()
                }
                
                VStack(spacing: 24) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    VStack(spacing: 16) {
                        Text("Welcome to PlayerPath!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text("Let's get you set up to begin tracking")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // Onboarding benefits
                VStack(alignment: .leading, spacing: 16) {
                    Text("What You Can Do:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    
                    FeatureHighlight(
                        icon: "person.crop.circle.badge.plus",
                        title: "Create Athlete Profiles",
                        description: "Track multiple players and their progress"
                    )
                    
                    FeatureHighlight(
                        icon: "video.circle.fill",
                        title: "Record & Analyze",
                        description: "Capture sessions and games"
                    )
                    
                    FeatureHighlight(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        title: "Track Statistics",
                        description: "Monitor batting averages and performance"
                    )
                    
                    FeatureHighlight(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Sync Everywhere",
                        description: "Access your data on all your devices"
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: completeOnboarding) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.headline)
                        Text("Get Started")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .accessibilityLabel("Complete onboarding and get started")
                .accessibilityHint("Completes the setup process and takes you to create your first athlete")
                .accessibilitySortPriority(1)
                
                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func completeOnboarding() {
        print("🟡 Completing athlete onboarding for new user...")
        
        Task {
            do {
                // Create onboarding progress record
                let progress = OnboardingProgress()
                progress.markCompleted()
                modelContext.insert(progress)
                
                try modelContext.save()
                print("🟢 Successfully saved onboarding progress")
                
                // Reset the new user flag after successful onboarding
                await MainActor.run {
                    authManager.resetNewUserFlag()
                    print("🟢 Reset new user flag, onboarding completed")
                    
                    // Provide haptic feedback
                    Haptics.medium()
                }
            } catch {
                print("🔴 Failed to save onboarding progress: \(error)")
            }
        }
    }
}

// MARK: - Coach Onboarding Flow
struct CoachOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // COACH BADGE - Makes it obvious this is the coach flow
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.caption)
                        Text("COACH ACCOUNT")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.2))
                    )
                    .foregroundColor(.green)
                    Spacer()
                }
                
                VStack(spacing: 24) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    VStack(spacing: 16) {
                        Text("Welcome, Coach!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text("Your coaching dashboard is ready")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // Coach-specific onboarding benefits
                VStack(alignment: .leading, spacing: 16) {
                    Text("As a Coach, You Can:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    
                    FeatureHighlight(
                        icon: "folder.badge.person.crop",
                        title: "Access Shared Folders",
                        description: "View folders shared with you by your athletes"
                    )
                    
                    FeatureHighlight(
                        icon: "video.badge.plus",
                        title: "Upload & Review Videos",
                        description: "Add videos and provide feedback"
                    )
                    
                    FeatureHighlight(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Annotate & Comment",
                        description: "Add coaching insights and notes"
                    )
                    
                    FeatureHighlight(
                        icon: "person.3.fill",
                        title: "Manage Multiple Athletes",
                        description: "Support all your athletes in one place"
                    )
                }
                .padding(.horizontal)
                
                // Info message
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How It Works")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Athletes share folders via email. They'll appear in your dashboard.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: completeCoachOnboarding) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.headline)
                        Text("Go to Dashboard")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .accessibilityLabel("Complete coach onboarding")
                .accessibilityHint("Takes you to your coaching dashboard")
                .accessibilitySortPriority(1)
                
                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func completeCoachOnboarding() {
        print("🟡 Completing coach onboarding for new user...")
        
        Task {
            do {
                // Create onboarding progress record
                let progress = OnboardingProgress()
                progress.markCompleted()
                modelContext.insert(progress)
                
                try modelContext.save()
                print("🟢 Successfully saved coach onboarding progress")
                
                // Reset the new user flag after successful onboarding
                await MainActor.run {
                    authManager.resetNewUserFlag()
                    authManager.markOnboardingComplete()
                    print("🟢 Reset new user flag, coach onboarding completed")
                    
                    // Provide haptic feedback
                    Haptics.medium()
                }
            } catch {
                print("🔴 Failed to save coach onboarding progress: \(error)")
            }
        }
    }
}

// MARK: - Authenticated Flow
struct AuthenticatedFlow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var users: [User]
    @Query(sort: \OnboardingProgress.createdAt, order: .forward) private var onboardingProgress: [OnboardingProgress]
    
    @State private var currentUser: User?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView(title: "Setting up your profile...", subtitle: "This will only take a moment")
            } else if let user = currentUser {
                let _ = print("🎯 AuthenticatedFlow - isNewUser: \(authManager.isNewUser), hasCompletedOnboarding: \(hasCompletedOnboarding), userRole: \(authManager.userRole.rawValue)")
                
                // Show onboarding for new users who haven't completed it yet
                if authManager.isNewUser && !hasCompletedOnboarding {
                    OnboardingFlow(user: user)
                } else {
                    UserMainFlow(
                        user: user,
                        isNewUserFlag: authManager.isNewUser,
                        hasCompletedOnboarding: hasCompletedOnboarding
                    )
                }
            } else {
                ErrorView(message: "Unable to load user profile") {
                    Task {
                        await authManager.signOut()
                    }
                }
            }
        }
        .task(priority: .userInitiated) {
            loadTask = Task {
                await loadUser()
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    // Computed property to check if onboarding has been completed
    private var hasCompletedOnboarding: Bool {
        // Check if onboarding progress exists or auth manager flag is set
        return onboardingProgress.contains { $0.hasCompletedOnboarding } || authManager.hasCompletedOnboarding
    }
    
    private func loadUser() async {
        guard let authUser = authManager.currentFirebaseUser,
              let rawEmail = authUser.email else {
            print("🔴 No authenticated user found")
            isLoading = false
            return
        }
        
        // Check for cancellation early
        guard !Task.isCancelled else {
            print("🟡 loadUser cancelled early")
            return
        }
        
        // Attach model context to auth manager for consistency
        authManager.attachModelContext(modelContext)
        
        let email = rawEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        #if DEBUG
        print("🟢 Looking up user with email: \(email)")
        #endif
        
        // Find or create user
        if let existingUser = users.first(where: { $0.email == email }) {
            #if DEBUG
            print("🟢 Found existing user: \(existingUser.username) (ID: \(existingUser.id))")
            print("🟢 User has \((existingUser.athletes ?? []).count) athletes")
            #endif
            
            // Check cancellation before updating state
            guard !Task.isCancelled else {
                print("🟡 loadUser cancelled before setting currentUser")
                return
            }
            
            currentUser = existingUser
            
            await MainActor.run {
                if let refreshedByEmail = users.first(where: { $0.email == email }) {
                    currentUser = refreshedByEmail
                    #if DEBUG
                    print("🟢 Using persisted user by email: \(refreshedByEmail.username) | athletes: \((refreshedByEmail.athletes ?? []).count)")
                    #endif
                } else if let refreshedByID = users.first(where: { $0.id == existingUser.id }) {
                    currentUser = refreshedByID
                    #if DEBUG
                    print("🟢 Fallback persisted user by id: \(refreshedByID.username) | athletes: \((refreshedByID.athletes ?? []).count)")
                    #endif
                } else {
                    #if DEBUG
                    print("🟠 Could not re-fetch persisted user; using in-memory instance")
                    #endif
                }
            }
        } else {
            #if DEBUG
            print("🟡 Creating new user")
            #endif
            
            // Check cancellation before creating
            guard !Task.isCancelled else {
                print("🟡 loadUser cancelled before createNewUser")
                return
            }
            
            await createNewUser(authUser: authUser, email: email)
        }
        
        // Final cancellation check before marking complete
        guard !Task.isCancelled else {
            print("🟡 loadUser cancelled before setting isLoading false")
            return
        }
        
        isLoading = false
    }
    
    private func createNewUser(authUser: FirebaseAuth.User, email: String) async {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newUser = User(
            username: authUser.displayName ?? normalizedEmail,
            email: normalizedEmail
        )
        
        modelContext.insert(newUser)
        
        do {
            try modelContext.save()
            #if DEBUG
            print("🟢 Successfully created new user with ID: \(newUser.id)")
            #endif
            
            // Attach the model context to auth manager for future use
            authManager.attachModelContext(modelContext)
            
            // Re-fetch the newly created user from the store using normalized email to ensure we use the persisted instance
            await MainActor.run {
                if let refreshed = users.first(where: { $0.email == normalizedEmail }) {
                    currentUser = refreshed
                    #if DEBUG
                    print("🟢 Using refreshed user: \(refreshed.id)")
                    #endif
                } else {
                    currentUser = newUser
                    #if DEBUG
                    print("🟠 Using original user instance: \(newUser.id)")
                    #endif
                }
            }
        } catch {
            print("🔴 Failed to create user: \(error)")
        }
    }
}

// MARK: - User Main Flow
struct UserMainFlow: View {
    let user: User
    let isNewUserFlag: Bool
    let hasCompletedOnboarding: Bool
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var sharedFolderManager = SharedFolderManager.shared
    @State private var selectedAthlete: Athlete?
    @State private var showCreationToast = false
    private let userID: UUID
    
    // NotificationCenter observer management using StateObject
    @StateObject private var notificationManager = NotificationObserverManager()
    
    init(user: User, isNewUserFlag: Bool, hasCompletedOnboarding: Bool) {
        self.user = user
        self.isNewUserFlag = isNewUserFlag
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userID = user.id
    }
    
    private var athletesForUser: [Athlete] {
        // Filter safely in Swift to avoid force unwrap in predicate
        allAthletes.filter { athlete in
            athlete.user?.id == userID
        }
    }
    
    private var resolvedAthlete: Athlete? {
        selectedAthlete ?? athletesForUser.first
    }
    
    var body: some View {
        Group {
            // IMPORTANT: Check if user is a coach FIRST before any athlete logic
            if authManager.userRole == .coach {
                CoachDashboardView()
                    .environmentObject(sharedFolderManager)
                    .onAppear {
                        print("🎯 UserMainFlow - Showing CoachDashboardView for user: \(user.email)")
                    }
            } 
            // Only check athlete-related logic if user is an athlete
            else if let athlete = resolvedAthlete {
                MainTabView(
                    user: user,
                    selectedAthlete: Binding(
                        get: { selectedAthlete ?? athlete },
                        set: { selectedAthlete = $0 }
                    )
                )
                .onAppear {
                    print("🎯 UserMainFlow - Showing MainTabView for athlete: \(athlete.name)")
                }
            } else if athletesForUser.count > 1 {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            } else if athletesForUser.isEmpty && isNewUserFlag && !hasCompletedOnboarding {
                // New athletes need to create their first athlete profile
                FirstAthleteCreationView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            } else {
                // Fallback: show athlete selection
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            }
        }
        .overlay(alignment: .top) {
            if showCreationToast {
                Text("Athlete created")
                    .font(.subheadline).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreationToast)
            }
        }
        .onChange(of: athletesForUser) { _, newValue in
            #if DEBUG
            print("🟡 Athletes changed for user \(user.id) (\(user.email)): \(newValue.count) athletes")
            for athlete in newValue {
                print("  - \(athlete.name) (ID: \(athlete.id), User: \(athlete.user?.email ?? "None"))")
            }
            #endif
            
            // If exactly one athlete exists and none is selected, select it.
            if selectedAthlete == nil, newValue.count == 1, let only = newValue.first {
                #if DEBUG
                print("🟢 Auto-selecting athlete: \(only.name) (ID: \(only.id))")
                #endif
                selectedAthlete = only
                showCreationToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showCreationToast = false
                }
            }
        }
        .task {
            // Use task modifier for automatic cancellation handling
            print("🎯 UserMainFlow - User role: \(authManager.userRole.rawValue)")
            print("🎯 UserMainFlow - User email: \(user.email)")
            print("🎯 UserMainFlow - Athletes count: \(athletesForUser.count)")
            
            setupNotificationObservers()
            
            #if DEBUG
            print("🟡 UserMainFlow task - User: \(user.id), Athletes: \(athletesForUser.count)")
            #endif
            if selectedAthlete == nil, athletesForUser.count == 1, let only = athletesForUser.first {
                #if DEBUG
                print("🟢 Task auto-selecting athlete: \(only.name) (ID: \(only.id))")
                #endif
                selectedAthlete = only
            }
        }
    }
    
    // MARK: - NotificationCenter Management
    
    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.showAthleteSelection) { _ in
            MainActor.assumeIsolated {
                selectedAthlete = nil
            }
        }
    }
}


// MARK: - Athlete Selection View
struct AthleteSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let user: User
    @Binding var selectedAthlete: Athlete?
    let authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    
    @State private var searchText: String = ""

    private var filteredAthletes: [Athlete] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return user.athletes ?? [] }
        return (user.athletes ?? []).filter { $0.name.lowercased().contains(q) }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if (user.athletes ?? []).isEmpty {
                    // This shouldn't happen with the new flow, but keeping as fallback
                    VStack(spacing: 30) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Add Your First Athlete")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Create a profile to start tracking baseball performance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: { showingAddAthlete = true }) {
                            Text("Add Athlete")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .accessibilityLabel("Add new athlete")
                        .accessibilityHint("Creates a new athlete profile to start tracking performance")
                        
                        HStack {
                            Image(systemName: "icloud")
                                .foregroundColor(.green)
                            Text("Videos will sync across devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        // Header for multiple athletes
                        VStack(spacing: 8) {
                            Text("Select Athlete")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Choose which athlete's profile to view")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top)
                        
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                ForEach(filteredAthletes) { athlete in
                                    AthleteCard(athlete: athlete) {
                                        selectedAthlete = athlete
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle((user.athletes ?? []).count > 1 ? "Choose Athlete" : "Athletes")
            .navigationBarTitleDisplayMode((user.athletes ?? []).count > 1 ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authManager.signOut()
                        }
                    }
                    .accessibilityLabel("Sign out")
                    .accessibilityHint("Sign out of your account")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if authManager.userRole == .athlete {
                        Button(action: { showingAddAthlete = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add athlete")
                        .accessibilityHint("Add a new athlete to your roster")
                    }
                }
            }
            .searchable(text: $searchText)
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: false)
        }
    }
}

// MARK: - Athlete Card View
struct AthleteCard: View {
    let athlete: Athlete
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // Profile icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 6) {
                    Text(athlete.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    if let created = athlete.createdAt {
                        Text("Created \(created, format: .dateTime.day().month().year())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Created —")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Quick stats if available
                HStack(spacing: 16) {
                    AthleteStatBadge(
                        icon: "video.fill",
                        count: (athlete.videoClips ?? []).count,
                        label: "Videos"
                    )
                    
                    AthleteStatBadge(
                        icon: "sportscourt.fill",
                        count: (athlete.games ?? []).count,
                        label: "Games"
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .appCard(cornerRadius: 16)
            .contextMenu {
                Button {
                    // Open
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                Button {
                    // Toggle live (stub)
                } label: {
                    Label((athlete.games ?? []).first?.isLive == true ? "End Live" : "Mark Live", systemImage: (athlete.games ?? []).first?.isLive == true ? "stop.circle" : "record.circle")
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Select athlete \(athlete.name)")
        .accessibilityHint("Opens this athlete’s dashboard")
    }
}

struct AthleteStatBadge: View {
    let icon: String
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AthleteRow: View {
    let athlete: Athlete
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(athlete.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let created = athlete.createdAt {
                        Text("Created \(created, format: .dateTime.day().month().year())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Created —")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 5)
        }
    }
}

struct AddAthleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @Binding var selectedAthlete: Athlete?
    let isFirstAthlete: Bool
    @State private var athleteName = ""
    @State private var showingSuccessAlert = false
    @State private var isCreatingAthlete = false
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""
    @State private var successMessage = ""
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                if authManager.userRole == .athlete {
                    Spacer()
                    
                    VStack(spacing: 24) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 100))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .green],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        VStack(spacing: 16) {
                            Text("Ready to Track!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Create your first profile to get started.")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What You Can Track:")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.bottom, 8)
                        
                        FeatureHighlight(
                            icon: "video.circle.fill",
                            title: "Record & Analyze",
                            description: "Capture sessions and games"
                        )
                        
                        FeatureHighlight(
                            icon: "chart.line.uptrend.xyaxis.circle.fill",
                            title: "Track Statistics",
                            description: "Monitor batting averages and performance metrics"
                        )
                        
                        FeatureHighlight(
                            icon: "arrow.triangle.2.circlepath.circle.fill",
                            title: "Sync Everywhere",
                            description: "Your data syncs securely across all devices"
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        TextField("Athlete Name", text: $athleteName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($isNameFieldFocused)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .onSubmit {
                                if isValidAthleteName(athleteName) && !isCreatingAthlete {
                                    saveAthlete()
                                }
                            }
                            .accessibilityLabel("Athlete name")
                            .accessibilityHint("Enter the athlete's name")
                        
                        Button(action: { Haptics.light(); saveAthlete() }) {
                            HStack {
                                if isCreatingAthlete {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                Text("Create First Athlete")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(!isValidAthleteName(athleteName) || isCreatingAthlete)
                        .accessibilityLabel("Create first athlete profile")
                        .accessibilityHint("Creates a new athlete profile to start tracking performance")
                        .accessibilityIdentifier("create_first_athlete")
                        .accessibilitySortPriority(1)
                    }
                    
                    Spacer()
                    
                    Text("You can add more athletes later in your profile settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    EmptyStateView(
                        systemImage: "person.fill.questionmark",
                        title: "Coach Accounts",
                        message: "Coaches don't create athletes. Ask your athletes to share a folder with you.",
                        actionTitle: nil,
                        action: nil
                    )
                    .padding()
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(isFirstAthlete ? "Get Started" : "New Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveAthlete) {
                        HStack {
                            if isCreatingAthlete {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isCreatingAthlete ? "Saving..." : "Save")
                        }
                    }
                    .disabled(!isValidAthleteName(athleteName) || isCreatingAthlete)
                    .accessibilityLabel("Save athlete")
                    .accessibilityHint("Creates the new athlete profile")
                }
            }
            .onAppear {
                // Auto-focus the name field when the view appears
                isNameFieldFocused = true
            }
        }
        .alert("Success! 🎉", isPresented: $showingSuccessAlert) {
            Button("Continue") {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .alert("Unable to Save Athlete", isPresented: $showingValidationError) {
            Button("OK") { }
        } message: {
            Text(validationErrorMessage)
        }
    }
    
    // MARK: - Validation Functions
    
    private func isValidAthleteName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Validation.isValidPersonName(trimmedName, min: 2, max: 50) && !isDuplicateAthleteName(trimmedName)
    }
    
    private func getNameValidationMessage(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return "Name cannot be empty"
        } else if trimmedName.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmedName.count > 50 {
            return "Name must be 50 characters or less"
        } else if !Validation.isValidPersonName(trimmedName, min: 2, max: 50) {
            return "Name can only contain letters, spaces, periods, hyphens, and apostrophes"
        } else if isDuplicateAthleteName(trimmedName) {
            return "An athlete with this name already exists"
        } else {
            return "Valid name"
        }
    }
    
    private func isDuplicateAthleteName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (user.athletes ?? []).contains { athlete in
            athlete.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedName
        }
    }
    
    private func saveAthlete() {
        // Final validation before saving
        let trimmedName = athleteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAthleteName(trimmedName) else {
            validationErrorMessage = getNameValidationMessage(trimmedName)
            showingValidationError = true
            return
        }
        isCreatingAthlete = true

        Task {
            let athlete = Athlete(name: trimmedName)
            
            // Set up relationship BEFORE inserting
            athlete.user = user
            
            // Insert in model context
            modelContext.insert(athlete)
            
            #if DEBUG
            print("🟡 Attempting to save athlete '\(trimmedName)' for user: \(user.id)")
            print("🟡 User email: \(user.email)")
            print("🟡 User currently has \((user.athletes ?? []).count) athletes")
            print("🟡 Firebase user: \(authManager.currentFirebaseUser?.email ?? "None")")
            #endif

            do {
                try modelContext.save()
                #if DEBUG
                print("🟢 Successfully saved athlete '\(trimmedName)' with ID: \(athlete.id)")
                #endif
                
                // SwiftData should have already updated the relationship via inverse
                // But we verify and log for debugging
                await MainActor.run {
                    #if DEBUG
                    print("🟢 User now has \((user.athletes ?? []).count) athletes")
                    #endif
                    
                    // Auto-select the new athlete
                    selectedAthlete = athlete
                    #if DEBUG
                    print("🟢 Selected new athlete: \(athlete.id)")
                    #endif
                }
                
                // If this was the first athlete, clear the new user flag so onboarding won't reappear
                if isFirstAthlete {
                    await MainActor.run {
                        authManager.resetNewUserFlag()
                        #if DEBUG
                        print("🟢 Reset new user flag")
                        #endif
                    }
                }
                
                // Haptics
                Haptics.medium()

                // Success messaging
                let message = isFirstAthlete
                    ? "Welcome to PlayerPath! Athlete '\(trimmedName)' has been created and you're ready to start tracking performance."
                    : "Athlete '\(trimmedName)' has been added successfully! You can now start tracking their performance."
                await MainActor.run {
                    successMessage = message
                    isCreatingAthlete = false
                    athleteName = ""
                    showingSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isCreatingAthlete = false
                    validationErrorMessage = getErrorMessage(for: error)
                    showingValidationError = true
                }
                print("🔴 Failed to save athlete: \(error)")
            }
        }
    }
    
    private func getErrorMessage(for error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("unique") || errorDescription.contains("duplicate") {
            return "An athlete with this name already exists. Please choose a different name."
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "Unable to save due to connection issues. Please check your internet and try again."
        } else {
            return "Unable to save athlete. Please try again in a moment."
        }
    }
}

// MARK: - Validation Requirement View
struct ValidationRequirement: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .foregroundColor(isMet ? .green : .gray)
        }
    }
}

// MARK: - Modern Video Quality Picker

/// Modern segmented picker for video quality selection with detailed information
struct VideoQualityPickerView: View {
    @Binding var selectedQuality: UIImagePickerController.QualityType
    @Environment(\.dismiss) private var dismiss
    
    // Quality mapping
    private let qualities: [UIImagePickerController.QualityType] = [
        .typeHigh, .typeMedium, .typeLow, .type640x480
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker section
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Quality")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text("Choose the video quality for your recordings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(qualities, id: \.self) { quality in
                            Text(qualityShortName(for: quality)).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Detail card section
                ScrollView {
                    VStack(spacing: 20) {
                        QualityDetailCard(quality: selectedQuality)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        
                        // Additional information
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Storage Impact", systemImage: "internaldrive")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            Text("Higher quality produces larger files. Choose based on your available storage and intended use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Quick comparison
                            VStack(alignment: .leading, spacing: 8) {
                                QualityComparisonRow(
                                    quality: .typeHigh,
                                    isSelected: selectedQuality == .typeHigh
                                )
                                QualityComparisonRow(
                                    quality: .typeMedium,
                                    isSelected: selectedQuality == .typeMedium
                                )
                                QualityComparisonRow(
                                    quality: .typeLow,
                                    isSelected: selectedQuality == .typeLow
                                )
                                QualityComparisonRow(
                                    quality: .type640x480,
                                    isSelected: selectedQuality == .type640x480
                                )
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Video Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save preference
                        UserDefaults.standard.set(selectedQuality.rawValue, forKey: "selectedVideoQuality")
                        Haptics.light()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedQuality)
    }
    
    private func qualityShortName(for quality: UIImagePickerController.QualityType) -> String {
        switch quality {
        case .typeHigh: return "High"
        case .typeMedium: return "Med"
        case .typeLow: return "Low"
        case .type640x480: return "SD"
        default: return "High"
        }
    }
}

// MARK: - Quality Detail Card

struct QualityDetailCard: View {
    let quality: UIImagePickerController.QualityType
    
    private var qualityInfo: (name: String, resolution: String, mbPerMinute: Double, maxSize: String, icon: String, color: Color, description: String) {
        switch quality {
        case .typeHigh:
            return ("High Quality", "1080p", 60.0, "600MB", "sparkles.tv.fill", .purple, "Best quality for sharing and editing")
        case .typeMedium:
            return ("Medium Quality", "720p", 25.0, "250MB", "tv.fill", .blue, "Good balance of quality and file size")
        case .typeLow:
            return ("Low Quality", "480p", 10.0, "100MB", "tv", .green, "Smaller files, faster uploads")
        case .type640x480:
            return ("SD Quality", "480p", 8.0, "80MB", "tv.and.mediabox", .orange, "Minimum quality for quick sharing")
        default:
            return ("High Quality", "1080p", 60.0, "600MB", "sparkles.tv.fill", .purple, "Best quality")
        }
    }
    
    var body: some View {
        let info = qualityInfo
        
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.title2)
                    .foregroundStyle(info.color)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(info.color.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(info.resolution)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .symbolEffect(.bounce, value: quality)
            }
            .padding()
            
            Divider()
            
            // Stats
            HStack(spacing: 0) {
                QualityStatItem(
                    icon: "arrow.down.circle.fill",
                    label: "Per Minute",
                    value: "~\(Int(info.mbPerMinute))MB",
                    color: info.color
                )
                
                Divider()
                    .frame(height: 50)
                
                QualityStatItem(
                    icon: "doc.fill",
                    label: "Max Size",
                    value: info.maxSize,
                    color: info.color
                )
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Description
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(info.color)
                
                Text(info.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
            .background(info.color.opacity(0.05))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(info.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Quality Stat Item

struct QualityStatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quality Comparison Row

struct QualityComparisonRow: View {
    let quality: UIImagePickerController.QualityType
    let isSelected: Bool
    
    private var qualityInfo: (name: String, size: String, color: Color) {
        switch quality {
        case .typeHigh:
            return ("High (1080p)", "~60MB/min", .purple)
        case .typeMedium:
            return ("Medium (720p)", "~25MB/min", .blue)
        case .typeLow:
            return ("Low (480p)", "~10MB/min", .green)
        case .type640x480:
            return ("SD (480p)", "~8MB/min", .orange)
        default:
            return ("High", "~60MB/min", .purple)
        }
    }
    
    var body: some View {
        let info = qualityInfo
        
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? info.color : Color(.systemGray4))
                .frame(width: 8, height: 8)
            
            Text(info.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fontWeight(isSelected ? .medium : .regular)
            
            Spacer()
            
            Text(info.size)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MainTabView
struct MainTabView: View {
    let user: User
    @Binding var selectedAthlete: Athlete
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var selectedTab: Int = MainTab.home.rawValue
    @State private var hideFloatingRecordButton = false
    @State private var showingSeasons = false
    @State private var showingCoaches = false
    @Environment(\.modelContext) private var modelContext
    
    // Swipe gesture tracking
    @GestureState private var dragOffset: CGFloat = 0
    @State private var tabTransition: AnyTransition = .identity
    
    // NotificationCenter observer management using StateObject for lifecycle safety
    @StateObject private var notificationManager = NotificationObserverManager()

    private func applyRecordedHitResult(_ info: [String: Any]) {
        guard let hitType = info["hitType"] as? String else { 
            print("⚠️ Invalid hit result format")
            return 
        }
        
        #if DEBUG
        print("⚾️ Recording hit result: \(hitType) for athlete: \(selectedAthlete.name)")
        #endif
        
        StatisticsHelpers.record(hitType: hitType, for: selectedAthlete, in: modelContext)
        
        // Provide haptic feedback for successful stat recording
        Haptics.success()
    }
    
    // MARK: - Dashboard actions
    private func toggleGameLive(_ game: Game) {
        Haptics.light()
        game.isLive.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle game live: \(error)") }
    }

    private func toggleTournamentActive(_ tournament: Tournament) {
        Haptics.light()
        tournament.isActive.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle tournament active: \(error)") }
    }
    
    // MARK: - Tab Navigation Helpers
    
    private func navigateToTab(_ direction: SwipeDirection) {
        let maxTab = MainTab.profile.rawValue
        var newTab = selectedTab
        
        switch direction {
        case .left:
            // Swipe left = next tab
            newTab = min(selectedTab + 1, maxTab)
        case .right:
            // Swipe right = previous tab
            newTab = max(selectedTab - 1, 0)
        }
        
        if newTab != selectedTab {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = newTab
            }
        }
    }
    
    private enum SwipeDirection {
        case left, right
    }
    
    var body: some View {
        tabViewContent
            .tint(.blue)
            .task {
                // Use task modifier which automatically handles cancellation
                restoreSelectedTab()
                setupNotificationObservers()
            }
            .onChange(of: selectedTab) { _, newValue in
                saveSelectedTab(newValue)
                // Reset when leaving Videos tab
                if newValue != MainTab.videos.rawValue { 
                    hideFloatingRecordButton = false 
                }
            }
            .sheet(isPresented: $showingSeasons) {
                SeasonsView(athlete: selectedAthlete)
            }
            .sheet(isPresented: $showingCoaches) {
                CoachesView(athlete: selectedAthlete)
            }
            .addKeyboardShortcuts()
    }
    
    // MARK: - NotificationCenter Management
    
    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.switchTab) { notification in
            MainActor.assumeIsolated {
                if let index = notification.object as? Int {
                    selectedTab = index
                    Haptics.light()
                }
            }
        }

        notificationManager.observe(name: Notification.Name.switchAthlete) { notification in
            MainActor.assumeIsolated {
                if let athlete = notification.object as? Athlete {
                    selectedAthlete = athlete
                    Haptics.light()
                }
            }
        }

        notificationManager.observe(name: Notification.Name.presentVideoRecorder) { _ in
            MainActor.assumeIsolated {
                selectedTab = MainTab.videos.rawValue
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.recordedHitResult) { notification in
            MainActor.assumeIsolated {
                if let info = notification.object as? [String: Any] {
                    applyRecordedHitResult(info)
                }
            }
        }

        notificationManager.observe(name: Notification.Name.videosManageOwnControls) { notification in
            MainActor.assumeIsolated {
                if let flag = notification.object as? Bool {
                    hideFloatingRecordButton = flag
                }
            }
        }

        notificationManager.observe(name: Notification.Name.presentSeasons) { _ in
            MainActor.assumeIsolated {
                showingSeasons = true
                Haptics.light()
            }
        }

        notificationManager.observe(name: Notification.Name.presentCoaches) { _ in
            MainActor.assumeIsolated {
                showingCoaches = true
                Haptics.light()
            }
        }
    }
    
    @ViewBuilder
    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            homeTab
            tournamentsTab
            gamesTab
            statsTab
            practiceTab
            videosTab
            highlightsTab
            moreTab
        }
    }
    
    private var homeTab: some View {
        NavigationStack {
            DashboardView(user: user, athlete: selectedAthlete, authManager: authManager)
        }
        .tabItem {
            Label("Home", systemImage: "house.fill")
        }
        .tag(MainTab.home.rawValue)
        .accessibilityLabel("Home tab")
        .accessibilityHint("View your dashboard and quick actions")
    }
    
    private var tournamentsTab: some View {
        NavigationStack {
            TournamentsView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Tournaments", systemImage: "trophy.fill")
        }
        .tag(MainTab.tournaments.rawValue)
        .accessibilityLabel("Tournaments tab")
        .accessibilityHint("View and manage tournaments")
    }
    
    private var gamesTab: some View {
        NavigationStack {
            GamesView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Games", systemImage: "baseball.fill")
        }
        .tag(MainTab.games.rawValue)
        .accessibilityLabel("Games tab")
        .accessibilityHint("View and manage games")
    }
    
    private var statsTab: some View {
        NavigationStack {
            StatisticsView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Stats", systemImage: "chart.bar.fill")
        }
        .tag(MainTab.stats.rawValue)
        .accessibilityLabel("Statistics tab")
        .accessibilityHint("View batting statistics and performance metrics")
    }
    
    private var practiceTab: some View {
        NavigationStack {
            PracticesView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Practice", systemImage: "figure.run")
        }
        .tag(MainTab.practice.rawValue)
        .accessibilityLabel("Practice tab")
        .accessibilityHint("View and manage practice sessions")
    }
    
    private var videosTab: some View {
        NavigationStack {
            VideoClipsView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Videos", systemImage: "video.fill")
        }
        .tag(MainTab.videos.rawValue)
        .accessibilityLabel("Videos tab")
        .accessibilityHint("View and record video clips")
    }
    
    private var highlightsTab: some View {
        NavigationStack {
            HighlightsView(athlete: selectedAthlete)
        }
        .tabItem {
            Label("Highlights", systemImage: "star.fill")
        }
        .tag(MainTab.highlights.rawValue)
        .accessibilityLabel("Highlights tab")
        .accessibilityHint("View your best plays and highlight reels")
    }
    
    private var moreTab: some View {
        NavigationStack {
            ProfileView(user: user, selectedAthlete: Binding(
                get: { selectedAthlete },
                set: { selectedAthlete = $0 ?? selectedAthlete }
            ))
        }
        .tabItem {
            Label("Profile", systemImage: "person.circle.fill")
        }
        .tag(MainTab.profile.rawValue)
        .accessibilityLabel("Profile tab")
        .accessibilityHint("Access your profile, settings, and additional features")
    }
    
    // MARK: - State Restoration
    
    private func saveSelectedTab(_ tab: Int) {
        UserDefaults.standard.set(tab, forKey: "LastSelectedTab")
    }
    
    private func restoreSelectedTab() {
        let savedTab = UserDefaults.standard.integer(forKey: "LastSelectedTab")
        // Only restore if it's a valid tab index
        if (0...MainTab.profile.rawValue).contains(savedTab) {
            selectedTab = savedTab
        }
    }
}

// MARK: - Keyboard Shortcuts Extension
extension View {
    @ViewBuilder
    func addKeyboardShortcuts() -> some View {
        self
            .keyboardShortcut("1", modifiers: .command)
            .keyboardShortcut("2", modifiers: .command)
            .keyboardShortcut("3", modifiers: .command)
            .keyboardShortcut("4", modifiers: .command)
            .keyboardShortcut("5", modifiers: .command)
            .keyboardShortcut("6", modifiers: .command)
            .keyboardShortcut("7", modifiers: .command)
            .keyboardShortcut("8", modifiers: .command)
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    let user: User
    let athlete: Athlete
    let authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingRecorderDirectly = false
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?
    
    var liveGames: [Game] {
        (athlete.games ?? [])
            .filter { $0.isLive }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else {
                    return lhs.date != nil
                }
                return lhsDate > rhsDate
            }
    }
    
    var liveTournaments: [Tournament] {
        (athlete.tournaments ?? [])
            .filter { $0.isActive }
            .sorted { lhs, rhs in
                let lhsDate = lhs.startDate ?? .distantPast
                let rhsDate = rhs.startDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }
    
    var recentGames: [Game] {
        let now = Date()
        return (athlete.games ?? [])
            .filter { game in
                guard let date = game.date else { return false }
                return date <= now
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else {
                    return lhs.date != nil
                }
                return lhsDate > rhsDate
            }
            .prefix(3)
            .map { $0 }
    }
    
    var upcomingGames: [Game] {
        let now = Date()
        return (athlete.games ?? [])
            .filter { game in
                guard let date = game.date else { return false }
                return date > now
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.date, let rhsDate = rhs.date else {
                    return lhs.date != nil
                }
                return lhsDate < rhsDate
            }
            .prefix(3)
            .map { $0 }
    }
    
    var recentVideos: [VideoClip] {
        (athlete.videoClips ?? [])
            .sorted { lhs, rhs in
                guard let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt else {
                    return lhs.createdAt != nil
                }
                return lhsCreated > rhsCreated
            }
            .prefix(3)
            .map { $0 }
    }
    
    // MARK: - Dashboard actions
    private func toggleGameLive(_ game: Game) {
        Haptics.light()
        game.isLive.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle game live: \(error)") }
    }

    private func toggleTournamentActive(_ tournament: Tournament) {
        Haptics.light()
        tournament.isActive.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle tournament active: \(error)") }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                
                // Live Section (Games and Tournaments)
                if !liveGames.isEmpty || !liveTournaments.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Live")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        // Display as vertical list for compactness
                        VStack(spacing: 8) {
                            ForEach(liveGames, id: \.id) { game in
                                NavigationLink {
                                    GameDetailView(game: game)
                                } label: {
                                    DashboardGameCard(
                                        game: game,
                                        onOpen: { /* Navigation handled by NavigationLink automatically */ },
                                        onToggleLive: { toggleGameLive(game) }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            ForEach(liveTournaments, id: \.id) { tournament in
                                NavigationLink {
                                    TournamentDetailView(tournament: tournament)
                                } label: {
                                    DashboardTournamentCard(
                                        tournament: tournament,
                                        onOpen: { /* Navigation handled by NavigationLink automatically */ },
                                        onToggleActive: { toggleTournamentActive(tournament) }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: liveGames.count + liveTournaments.count)
                }
                
                // Quick Actions Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Quick Actions")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        QuickActionButton(
                            icon: "plus.circle.fill",
                            title: "New Game",
                            color: .blue
                        ) {
                            Task { @MainActor in
                                // Switch to Games tab
                                postSwitchTab(.games)
                                #if DEBUG
                                print("🎮 New Game quick action - switching to Games tab")
                                #endif
                                
                                // Check if there's a live tournament to associate with the new game
                                let tournamentContext = liveTournaments.first
                                
                                // Ask the Games module to present its Add Game UI
                                // Pass the live tournament as context if available
                                NotificationCenter.default.post(name: Notification.Name.presentAddGame, object: tournamentContext)
                                #if DEBUG
                                if let tournament = tournamentContext {
                                    print("📣 Posted .presentAddGame notification with live tournament: \(tournament.name)")
                                } else {
                                    print("📣 Posted .presentAddGame notification with no tournament context")
                                }
                                #endif
                                Haptics.light()
                            }
                        }
                        QuickActionButton(
                            icon: liveGames.isEmpty ? "video.badge.plus" : "record.circle",
                            title: liveGames.isEmpty ? "Quick Record" : "Record Live",
                            color: .red
                        ) {
                            Task { @MainActor in
                                #if DEBUG
                                print("🎬 Quick Record tapped - Live games: \(liveGames.count)")
                                #endif
                                
                                // Check permissions first (before any UI changes)
                                let status = await RecorderPermissions.ensureCapturePermissions(context: "VideoRecorder")
                                guard status == .granted else {
                                    #if DEBUG
                                    print("🛑 Permissions not granted for recording")
                                    #endif
                                    return
                                }
                                
                                // Set the live game context for recording
                                let gameContext: Game? = liveGames.first
                                #if DEBUG
                                if let game = gameContext {
                                    print("🎮 Recording for live game: \(game.opponent)")
                                } else {
                                    print("🎬 No live games - quick record mode")
                                }
                                #endif
                                
                                // Switch to Videos tab
                                postSwitchTab(.videos)
                                
                                // Add a small delay to ensure the Videos tab is ready before posting notification
                                // This ensures VideoClipsView has mounted and is listening for the notification
                                try? await Task.sleep(for: .milliseconds(150))
                                
                                // Post notification with game context
                                // The Videos tab will handle this when it appears
                                NotificationCenter.default.post(name: Notification.Name.presentVideoRecorder, object: gameContext)
                                #if DEBUG
                                print("📣 Posted .presentVideoRecorder notification with game context")
                                #endif
                                Haptics.light()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Management Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Management")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        DashboardFeatureCard(
                            icon: "trophy.fill",
                            title: "Tournaments",
                            subtitle: "\((athlete.tournaments ?? []).count) Total",
                            color: .orange
                        ) {
                            postSwitchTab(.tournaments)
                        }

                        DashboardFeatureCard(
                            icon: "sportscourt.fill",
                            title: "Games",
                            subtitle: "\((athlete.games ?? []).count) Total",
                            color: .blue
                        ) {
                            postSwitchTab(.games)
                        }

                        DashboardFeatureCard(
                            icon: "figure.run",
                            title: "Practice",
                            subtitle: "0 Sessions",
                            color: .green
                        ) {
                            postSwitchTab(.practice)
                        }

                        DashboardFeatureCard(
                            icon: "video.fill",
                            title: "Video Clips",
                            subtitle: "\((athlete.videoClips ?? []).count) Recorded",
                            color: .purple
                        ) {
                            postSwitchTab(.videos)
                        }

                        DashboardFeatureCard(
                            icon: "star.fill",
                            title: "Highlights",
                            subtitle: "\((athlete.videoClips ?? []).filter { $0.isHighlight }.count) Highlights",
                            color: .yellow
                        ) {
                            // For now, route to Highlights tab
                            postSwitchTab(.highlights)
                        }

                        DashboardFeatureCard(
                            icon: "chart.bar.fill",
                            title: "Statistics",
                            subtitle: (athlete.statistics.map { String(format: "%.3f AVG", $0.battingAverage) }) ?? "0.000 AVG",
                            color: .blue
                        ) {
                            postSwitchTab(.stats)
                        }
                        
                        DashboardFeatureCard(
                            icon: "calendar",
                            title: "Seasons",
                            subtitle: "\((athlete.seasons ?? []).count) Total",
                            color: .teal
                        ) {
                            // Switch to home tab first, then present sheet
                            postSwitchTab(.home)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(name: Notification.Name.presentSeasons, object: athlete)
                            }
                        }
                        
                        DashboardFeatureCard(
                            icon: "person.3.fill",
                            title: "Coaches",
                            subtitle: "0 Coaches",
                            color: .indigo
                        ) {
                            // Switch to home tab first, then present sheet
                            postSwitchTab(.home)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(name: Notification.Name.presentCoaches, object: athlete)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Quick Stats Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Quick Stats")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        DashboardStatCard(
                            title: "AVG",
                            value: athlete.statistics.map { String(format: "%.3f", $0.battingAverage) } ?? "0.000",
                            icon: "square.grid.2x2.fill",
                            color: .blue
                        )
                        DashboardStatCard(
                            title: "SLG",
                            value: athlete.statistics.map { String(format: "%.3f", $0.sluggingPercentage) } ?? "0.000",
                            icon: "chart.bar.fill",
                            color: .purple
                        )
                        DashboardStatCard(
                            title: "Hits",
                            value: athlete.statistics.map { String($0.hits) } ?? "0",
                            icon: "hand.tap.fill",
                            color: .green
                        )
                    }
                }
                .padding(.horizontal)
                
                // Recent Videos Section
                if !recentVideos.isEmpty {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Recent Videos")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                            NavigationLink {
                                VideoClipsView(athlete: athlete)
                            } label: {
                                Text("See All")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
                        }
                        .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                let videos = Array(recentVideos)
                                ForEach(videos, id: \.id) { video in
                                    DashboardVideoCard(video: video)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: recentVideos.count)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            refreshTask?.cancel()
            refreshTask = Task {
                await refreshDashboard()
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(athlete.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    // Show all athletes with checkmark for current
                    ForEach((user.athletes ?? []).sorted(by: { $0.name < $1.name })) { ath in
                        Button {
                            // Switch to this athlete
                            NotificationCenter.default.post(
                                name: Notification.Name.switchAthlete,
                                object: ath
                            )
                            Haptics.light()
                        } label: {
                            HStack {
                                Text(ath.name)
                                if ath.id == athlete.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                        Haptics.light()
                    } label: {
                        Label("Manage Athletes", systemImage: "person.2.fill")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(athlete.name)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Refresh Handler
    
    func refreshDashboard() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        defer { isRefreshing = false }
        
        // Check for cancellation
        guard !Task.isCancelled else { return }
        
        // Haptic feedback for refresh
        await MainActor.run {
            Haptics.light()
        }
        
        // Simulate data refresh with a small delay for better UX
        try? await Task.sleep(for: .milliseconds(500))
        
        // Check cancellation after sleep
        guard !Task.isCancelled else { return }
        
        // SwiftData will automatically refresh on next query
        await MainActor.run {
            Haptics.light()
        }
    }
}

// MARK: - Dashboard Helper Views

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .appCard()
        .accessibilityElement(children: .combine)
    }
}

struct DashboardGameCard: View {
    let game: Game
    var onOpen: (() -> Void)? = nil
    var onToggleLive: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Game icon indicator
            Image(systemName: "baseball.fill")
                .font(.title3)
                .foregroundColor(game.isLive ? .red : .blue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(game.isLive ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if game.isLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .symbolEffect(.pulse, options: .repeating)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                                .textCase(.uppercase)
                        }
                    }
                    
                    Text("GAME")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                
                // Opponent name
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Date information
                if let date = game.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Date TBD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(game.isLive ? Color.red.opacity(0.05) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(game.isLive ? Color.red.opacity(0.3) : Color(.systemGray5), lineWidth: game.isLive ? 1.5 : 1)
        )
        .contextMenu {
            Button {
                Haptics.light()
                onOpen?()
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
                    .accessibilityLabel("Open game")
            }
            Button {
                toggleHapticThen(onToggleLive)
            } label: {
                Label(game.isLive ? "End Live" : "Mark Live", systemImage: game.isLive ? "stop.circle" : "record.circle")
                    .accessibilityLabel("Toggle live status")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(game.isLive ? "Live game against \(game.opponent)" : "Game against \(game.opponent)")
    }
    
    private func toggleHapticThen(_ action: (() -> Void)?) { Haptics.light(); action?() }
}

struct DashboardTournamentCard: View {
    let tournament: Tournament
    var onOpen: (() -> Void)? = nil
    var onToggleActive: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Tournament icon indicator
            Image(systemName: "trophy.fill")
                .font(.title3)
                .foregroundColor(tournament.isActive ? .orange : .orange.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(tournament.isActive ? Color.orange.opacity(0.15) : Color.orange.opacity(0.08))
                )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if tournament.isActive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .symbolEffect(.pulse, options: .repeating)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .textCase(.uppercase)
                        }
                    }
                    
                    Text("TOURNAMENT")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                
                // Tournament name
                Text(tournament.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Date information
                if let start = tournament.startDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(start, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Date TBD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tournament.isActive ? Color.orange.opacity(0.05) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tournament.isActive ? Color.orange.opacity(0.3) : Color(.systemGray5), lineWidth: tournament.isActive ? 1.5 : 1)
        )
        .contextMenu {
            Button {
                Haptics.light()
                onOpen?()
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
                    .accessibilityLabel("Open tournament")
            }
            Button {
                Haptics.light()
                onToggleActive?()
            } label: {
                Label(tournament.isActive ? "End" : "Mark Active", systemImage: tournament.isActive ? "stop.circle" : "record.circle")
                    .accessibilityLabel("Toggle tournament active status")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tournament.isActive ? "Live tournament: \(tournament.name)" : "Tournament: \(tournament.name)")
    }
}

// MARK: - DashboardVideoThumbnail (new reusable thumbnail view)
struct DashboardVideoThumbnail: View {
    let video: VideoClip
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .transition(.opacity.combined(with: .scale))
            } else {
                LinearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .transition(.opacity)
            }

            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.white)
                .shadow(radius: 2)
                .symbolEffect(.bounce, options: .speed(0.5))
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task { await load() }
    }

    private func load() async {
        guard !isLoading, image == nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        guard let path = video.thumbnailPath else { return }
        
        do {
            let img = try await ThumbnailCache.shared.loadThumbnail(at: path)
            await MainActor.run { 
                withAnimation(.easeInOut(duration: 0.2)) { 
                    image = img 
                } 
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to load thumbnail: \(error.localizedDescription)")
            #endif
        }
    }
}

struct DashboardVideoCard: View {
    let video: VideoClip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video thumbnail placeholder replaced by DashboardVideoThumbnail
            DashboardVideoThumbnail(video: video)
                .accessibilityLabel("Video thumbnail")
            
            Text(video.playResult?.type.displayName ?? video.fileName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            if let created = video.createdAt {
                Text(created, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 140)
        .padding(8)
        .appCard()
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                Haptics.light()
                NotificationCenter.default.post(name: Notification.Name.presentFullscreenVideo, object: video)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            
            if FileManager.default.fileExists(atPath: video.filePath) {
                ShareLink(item: URL(fileURLWithPath: video.filePath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("File unavailable")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .buttonStyle(.plain)
    }
}

// MARK: - PracticeView (New placeholder view added at end)
struct PracticeView: View {
    let athlete: Athlete
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Practice")
                .font(.title)
                .fontWeight(.bold)
            Text("Practice tracking coming soon for \(athlete.name)")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - DashboardFeatureCard (New reusable component added)

struct DashboardFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .appCard()
        .accessibilityElement(children: .combine)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}

// MARK: - RoleSelectionButton

struct RoleSelectionButton: View {
    let role: UserRole
    let isSelected: Bool
    let icon: String
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .blue)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(description)")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}


// MARK: - Coach Dashboard View
// NOTE: This old implementation has been replaced by CoachDashboardView.swift
// Keeping it commented out for reference during migration

/*
struct CoachDashboardView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var sharedFolders: [SharedFolder] = []
    @State private var pendingInvitations: [CoachInvitation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Welcome Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.gearshape")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Coach Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let displayName = authManager.currentFirebaseUser?.displayName {
                            Text("Welcome, \(displayName)")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top)
                    
                    // Pending Invitations Section
                    if !pendingInvitations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Pending Invitations", systemImage: "envelope.badge")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            ForEach(pendingInvitations) { invitation in
                                PendingInvitationCard(invitation: invitation) {
                                    acceptInvitation(invitation)
                                }
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Shared Folders Section
                    if isLoading {
                        ProgressView("Loading your folders...")
                            .padding()
                    } else if sharedFolders.isEmpty && pendingInvitations.isEmpty {
                        EmptyStateView(
                            systemImage: "folder.badge.questionmark",
                            title: "No Shared Folders Yet",
                            message: "Athletes will share their folders with you. Once they do, they'll appear here.",
                            actionTitle: nil,
                            action: nil
                        )
                        .padding()
                    } else if !sharedFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("My Athletes", systemImage: "folder.badge.person.crop")
                                .font(.headline)
                            
                            ForEach(sharedFolders) { folder in
                                SharedFolderCard(folder: folder)
                            }
                        }
                        .padding()
                    }
                    
                    // Error Message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await authManager.signOut()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .refreshable {
                await loadData()
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        guard let userID = authManager.userID else {
            errorMessage = "Not signed in"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Load shared folders
            let folders = try await FirestoreManager.shared.fetchSharedFolders(forCoach: userID)
            
            // Load pending invitations
            if let email = authManager.currentFirebaseUser?.email {
                let invitations = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
                await MainActor.run {
                    self.sharedFolders = folders
                    self.pendingInvitations = invitations
                }
            }
            
            isLoading = false
        } catch {
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func acceptInvitation(_ invitation: CoachInvitation) {
        guard let userID = authManager.userID,
              let invitationID = invitation.id else {
            return
        }
        
        Task {
            do {
                try await FirestoreManager.shared.acceptInvitation(
                    invitationID: invitationID,
                    coachID: userID,
                    permissions: .default
                )
                
                // Reload data
                await loadData()
                
                Haptics.success()
            } catch {
                errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
            }
        }
    }
}
*/

// MARK: - Shared Folder Card

struct SharedFolderCard: View {
    let folder: SharedFolder
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                
                Text(folder.name)
                    .font(.headline)
                
                Spacer()
                
                if let videoCount = folder.videoCount {
                    Text("\(videoCount) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let updatedAt = folder.updatedAt {
                Text("Last updated: \(updatedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .appCard()
    }
}

// MARK: - Pending Invitation Card

struct PendingInvitationCard: View {
    let invitation: CoachInvitation
    let onAccept: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.athleteName)
                        .font(.headline)
                    
                    Text("Folder: \(invitation.folderName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onAccept) {
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            
            Text("Invited: \(invitation.createdAt, format: .relative(presentation: .named))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Live Game Recording Flow Documentation
// 
// Complete flow for "Record Live" when a game is live:
// 1. Dashboard detects live games and shows "Record Live" quick action
// 2. User taps "Record Live" → Dashboard gets first live game
// 3. Dashboard checks permissions, switches to Videos tab, and posts .presentVideoRecorder with game object
// 4. VideoClipsView receives notification and opens VideoRecorderView_Refactored with live game context
// 5. VideoRecorderView_Refactored shows "LIVE GAME vs [opponent]" header and auto-opens camera
// 6. User records video → PlayResultOverlayView links video to the live game
// 7. Video is saved with game context and statistics are updated automatically
//
// MARK: - TODO Integration Notes
// Elsewhere in your project:
// - Videos feature should observe Notification.Name("PresentVideoRecorder") to present the recorder UI.
// - When analysis determines a hit result, post Notification.Name("RecordedHitResult") with object ["hitType": String].
// - Highlights feature should, upon receiving RecordedHitResult, move the associated clip to a Highlights collection/folder.
// - Statistics feature should, upon receiving RecordedHitResult, increment the appropriate stat (1B/2B/3B/HR) and recompute AVG/SLG.
// - Games feature should observe Notification.Name("PresentAddGame") to present the Add Game sheet immediately when arriving on the Games tab.
// - GameDetailView can post Notification.Name("ReactivateGame") with the game ID/object to mark a game live again if it was ended by mistake.
// - Videos feature should observe Notification.Name("PresentFullscreenVideo") to present the player in full screen for a given clip.

// Integration: In VideoClipsView or its recorder container, post .videosManageOwnControls with true when showing its own Record/Upload buttons, and false when dismissed:
// NotificationCenter.default.post(name: Notification.Name.videosManageOwnControls, object: true)
// NotificationCenter.default.post(name: Notification.Name.videosManageOwnControls, object: false)

// To play a video fullscreen from anywhere:
// NotificationCenter.default.post(name: Notification.Name.presentFullscreenVideo, object: videoClip)



#Preview("Main App") {
    PlayerPathMainView()
        .environmentObject(ComprehensiveAuthManager())
        .dynamicTypeSize(.large ... .accessibility3)
}

#Preview("Video Quality Picker") {
    struct PreviewWrapper: View {
        @State private var quality: UIImagePickerController.QualityType = .typeHigh
        
        var body: some View {
            VideoQualityPickerView(selectedQuality: $quality)
        }
    }
    
    return PreviewWrapper()
}

