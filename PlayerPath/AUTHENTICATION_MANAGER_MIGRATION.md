# AuthenticationManager Migration Guide

## Overview

The `AuthenticationManager` has been significantly enhanced with critical fixes and new features. This guide helps you migrate existing code to use the improved API.

---

## 🔄 Breaking Changes

### None! 

All existing APIs remain backward compatible. The following are **additions** only:

---

## ✅ What Stays The Same

### Basic Authentication
```swift
// These work exactly as before
await authManager.signIn(email: email, password: password)
await authManager.signUp(email: email, password: password, displayName: name)
await authManager.signOut()
await authManager.sendPasswordReset(email: email)

// These properties work as before
authManager.isAuthenticated
authManager.currentFirebaseUser
authManager.isLoading
authManager.errorMessage
```

---

## 🆕 New Features to Adopt

### 1. SwiftData Integration

**New:** Attach model context for automatic User management

```swift
// OLD: Manual user management
@Environment(\.modelContext) private var modelContext

var body: some View {
    ContentView()
        .task {
            if authManager.isAuthenticated {
                await loadUser()  // Manual
            }
        }
}

// NEW: Automatic user management
@Environment(\.modelContext) private var modelContext
@EnvironmentObject var authManager: AuthenticationManager

var body: some View {
    ContentView()
        .onAppear {
            // Attach once, users loaded automatically
            authManager.attachModelContext(modelContext)
        }
}

// Access the current user directly
if let user = authManager.currentUser {
    Text("Welcome, \(user.username)")
}
```

### 2. New Convenience Properties

```swift
// NEW: Easy access to user info
if let email = authManager.userEmail {
    Text("Email: \(email)")
}

if let name = authManager.displayName {
    Text("Name: \(name)")
}

if authManager.isEmailVerified {
    Image(systemName: "checkmark.seal.fill")
}
```

### 3. Email Verification

```swift
// NEW: Email verification support
Button("Verify Email") {
    Task {
        do {
            try await authManager.sendEmailVerification()
            // Show success message
        } catch {
            // Handle error
        }
    }
}

// Check verification status
if !authManager.isEmailVerified {
    VerificationBanner()
}
```

### 4. Display Name Updates

```swift
// NEW: Update display name
TextField("Display Name", text: $newName)

Button("Save") {
    Task {
        do {
            try await authManager.updateDisplayName(newName)
            // Success
        } catch {
            // Handle error
        }
    }
}
```

### 5. Reauthentication

```swift
// NEW: Reauthenticate for sensitive operations
Button("Delete Account") {
    Task {
        do {
            // Reauthenticate first
            try await authManager.reauthenticate(password: currentPassword)
            
            // Then perform sensitive operation
            try await authManager.deleteAccount()
        } catch AuthManagerError.wrongPassword {
            showError = "Incorrect password"
        } catch AuthManagerError.requiresRecentLogin {
            showError = "Please sign in again to continue"
        } catch {
            showError = "Failed to delete account"
        }
    }
}
```

### 6. Account Deletion

```swift
// NEW: Delete account support
Button("Delete My Account", role: .destructive) {
    showDeleteConfirmation = true
}
.confirmationDialog(
    "Delete Account?",
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete Forever", role: .destructive) {
        Task {
            do {
                try await authManager.deleteAccount()
            } catch {
                showError = true
            }
        }
    }
}
```

### 7. User Refresh

```swift
// NEW: Refresh user data (e.g., after email verification)
Button("I've Verified My Email") {
    Task {
        do {
            try await authManager.refreshUser()
            
            if authManager.isEmailVerified {
                showSuccess = "Email verified!"
            }
        } catch {
            showError = "Couldn't refresh. Please try again."
        }
    }
}
```

---

## 🔧 Recommended Improvements to Existing Code

### Improve Error Handling

```swift
// BEFORE: Generic error display
if let error = authManager.errorMessage {
    Text(error)
        .foregroundColor(.red)
}

// AFTER: Structured error handling
if let error = authManager.errorMessage {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Sign In Failed")
                .fontWeight(.semibold)
        }
        
        Text(error)
            .font(.subheadline)
            .foregroundColor(.secondary)
        
        Button("Try Again") {
            authManager.errorMessage = nil
        }
        .buttonStyle(.bordered)
    }
    .padding()
    .background(Color.orange.opacity(0.1))
    .cornerRadius(12)
}
```

### Add Loading States

```swift
// BEFORE: Basic loading
if authManager.isLoading {
    ProgressView()
}

// AFTER: Informative loading
if authManager.isLoading {
    VStack(spacing: 12) {
        ProgressView()
            .scaleEffect(1.5)
        Text("Signing in...")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.2))
}
```

### Handle Sign Out Properly

```swift
// BEFORE: Sync sign out
Button("Sign Out") {
    authManager.signOut()
}

// AFTER: Async sign out with feedback
Button("Sign Out") {
    Task {
        await authManager.signOut()
        
        if authManager.errorMessage == nil {
            // Show success toast or navigate away
            Haptics.success()
        }
    }
}
```

---

## 🎯 Best Practices

### 1. Always Use Task for Auth Operations

```swift
// ✅ GOOD
Button("Sign In") {
    Task {
        await authManager.signIn(email: email, password: password)
    }
}

// ❌ BAD - Don't call async directly
Button("Sign In") {
    authManager.signIn(email: email, password: password)  // Won't compile
}
```

### 2. Check isAuthenticated Before Accessing User

```swift
// ✅ GOOD
if authManager.isAuthenticated {
    if let user = authManager.currentUser {
        Text("Welcome, \(user.username)")
    }
}

// ⚠️ RISKY - currentUser might be nil even if authenticated
// (if model context wasn't attached)
Text("Welcome, \(authManager.currentUser?.username ?? "Guest")")
```

### 3. Attach Model Context Early

```swift
// ✅ GOOD - Attach in app root
@main
struct MyApp: App {
    @StateObject private var authManager = AuthenticationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .modelContainer(for: [User.self, Athlete.self])
                .onAppear {
                    // Attach context right away
                    if let context = authManager.currentUser?.modelContext {
                        authManager.attachModelContext(context)
                    }
                }
        }
    }
}
```

### 4. Handle Errors with Specific Types

```swift
// ✅ GOOD - Type-safe error handling
do {
    try await authManager.reauthenticate(password: password)
} catch AuthManagerError.wrongPassword {
    errorMessage = "Incorrect password"
} catch AuthManagerError.requiresRecentLogin {
    errorMessage = "Please sign in again"
} catch {
    errorMessage = "An unexpected error occurred"
}

// ⚠️ OKAY - Generic error handling
do {
    try await authManager.reauthenticate(password: password)
} catch {
    errorMessage = error.localizedDescription
}
```

### 5. Clear Errors on User Action

```swift
// ✅ GOOD - Clear errors when user retries
Button("Sign In") {
    authManager.errorMessage = nil  // Clear previous error
    Task {
        await authManager.signIn(email: email, password: password)
    }
}
```

---

## 🧪 Testing Recommendations

### Test Auth Flows

```swift
@MainActor
class AuthenticationTests: XCTestCase {
    var authManager: AuthenticationManager!
    
    override func setUp() {
        authManager = AuthenticationManager()
    }
    
    func testSignInValidation() async {
        // Test empty email
        await authManager.signIn(email: "", password: "test")
        XCTAssertNotNil(authManager.errorMessage)
        
        // Test invalid email
        await authManager.signIn(email: "notanemail", password: "test")
        XCTAssertNotNil(authManager.errorMessage)
    }
    
    func testTaskCancellation() async {
        let task = Task {
            await authManager.signIn(email: "test@test.com", password: "test")
        }
        
        task.cancel()
        
        // Should not crash or leak memory
    }
}
```

---

## 📋 Migration Checklist

Use this checklist to ensure you've fully adopted the new features:

- [ ] Model context attached in app root
- [ ] Using `currentUser` property instead of manual user fetching
- [ ] Email verification flow implemented
- [ ] Reauthentication added for sensitive operations
- [ ] Account deletion option available in settings
- [ ] Error handling uses specific error types
- [ ] Loading states are informative
- [ ] Sign out is async with proper feedback
- [ ] All auth calls wrapped in Task { }
- [ ] Errors cleared on user retry
- [ ] Auth flows tested with cancellation

---

## 🆘 Common Migration Issues

### Issue: currentUser is always nil

**Cause:** Model context not attached

**Fix:**
```swift
.onAppear {
    authManager.attachModelContext(modelContext)
}
```

### Issue: Errors not showing

**Cause:** Not checking errorMessage reactively

**Fix:**
```swift
.onChange(of: authManager.errorMessage) { _, newValue in
    if let error = newValue {
        showAlert = true
        alertMessage = error
    }
}
```

### Issue: Loading state stuck

**Cause:** Task was cancelled but loading not cleared

**Fix:** Already handled in new implementation! Cancellation now properly cleans up loading state.

### Issue: Auth state not updating

**Cause:** Auth listener not started (unlikely with new implementation)

**Fix:** Already handled in new implementation with proper initialization order.

---

## 📞 Support

If you encounter issues during migration:

1. Check the debug console for 🔐 Auth logs
2. Verify model context is attached
3. Ensure all async calls are wrapped in Task { }
4. Review the AUTHENTICATION_MANAGER_FIXES.md documentation

---

## ✅ Migration Complete!

Once you've:
- Attached model context
- Adopted new convenience properties
- Implemented email verification
- Added reauthentication for sensitive ops

You're fully migrated and can take advantage of all the new features and fixes!

