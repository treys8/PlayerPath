# Phase 1: Firebase Foundation - Implementation Guide

**Project:** PlayerPath Baseball App  
**Phase:** Firebase Foundation Setup  
**Date:** November 21, 2025  
**Status:** Ready to Implement

---

## 📋 Overview

This guide walks you through setting up the Firebase foundation for coach-athlete collaboration. By the end of Phase 1, you'll have:

✅ Firebase SDK properly integrated  
✅ Firestore database with security rules  
✅ Role-based authentication (athlete/coach)  
✅ User profile management in Firestore  
✅ All backend infrastructure ready for Phase 2

---

## ✅ Current Status Check

### What You Already Have:
- ✅ `FirestoreManager.swift` - Complete Firestore service layer
- ✅ `ComprehensiveAuthManager.swift` - Firebase Auth with role support
- ✅ `SharedFolderManager.swift` - Sharing logic implemented
- ✅ Coach onboarding flow (separate from athlete flow)
- ✅ Firebase initialization in app

### What We Need to Complete:
1. Add Firestore SDK to project (if not already installed)
2. Configure Firestore in Firebase Console
3. Add Security Rules
4. Test role-based authentication
5. Verify Firestore read/write permissions

---

## 🛠️ Step 1: Add Firebase SDK

### Option A: Using Swift Package Manager (Recommended)

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the Firebase URL: `https://github.com/firebase/firebase-ios-sdk`
4. Select version: **10.19.0** or later
5. Add these packages:
   - ✅ `FirebaseAuth`
   - ✅ `FirebaseFirestore`
   - ✅ `FirebaseStorage`
   - ✅ `FirebaseAnalytics` (optional)
   - ✅ `FirebaseMessaging` (for push notifications later)

### Verify Installation

Check that your imports work in `FirestoreManager.swift`:

```swift
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
```

---

## 🔧 Step 2: Configure Firestore in Firebase Console

### 2.1 Enable Firestore Database

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your **PlayerPath** project
3. Navigate to **Build → Firestore Database**
4. Click **Create database**
5. Choose **Start in production mode** (we'll add security rules next)
6. Select a region closest to your users (e.g., `us-central1`)

### 2.2 Enable Firebase Authentication

1. Navigate to **Build → Authentication**
2. Click **Get started**
3. Enable **Email/Password** provider:
   - Toggle **Email/Password** to **Enabled**
   - Leave **Email link** disabled for now
4. (Optional) Enable **Apple Sign-In** if not already done

### 2.3 Enable Firebase Storage

1. Navigate to **Build → Storage**
2. Click **Get started**
3. Choose **Start in production mode** (we'll add rules)
4. Use the same region as Firestore

---

## 🔒 Step 3: Add Firestore Security Rules

### 3.1 Navigate to Rules Editor

1. In Firebase Console, go to **Firestore Database**
2. Click the **Rules** tab
3. Replace the default rules with the following:

### 3.2 Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // ============================================
    // Helper Functions
    // ============================================
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userID) {
      return request.auth.uid == userID;
    }
    
    function isPremium() {
      let user = get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
      return user.isPremium == true;
    }
    
    function getUserRole() {
      let user = get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
      return user.role;
    }
    
    function isCoach() {
      return getUserRole() == "coach";
    }
    
    function isAthlete() {
      return getUserRole() == "athlete";
    }
    
    function canAccessFolder(folderID) {
      let folder = get(/databases/$(database)/documents/sharedFolders/$(folderID)).data;
      return request.auth.uid == folder.ownerAthleteID 
          || request.auth.uid in folder.sharedWithCoachIDs;
    }
    
    function canUploadToFolder(folderID) {
      let folder = get(/databases/$(database)/documents/sharedFolders/$(folderID)).data;
      // Owner can always upload
      if (request.auth.uid == folder.ownerAthleteID) {
        return true;
      }
      // Coach can upload if they have permission
      if (request.auth.uid in folder.sharedWithCoachIDs) {
        return folder.permissions[request.auth.uid].canUpload == true;
      }
      return false;
    }
    
    function canDeleteFromFolder(folderID) {
      let folder = get(/databases/$(database)/documents/sharedFolders/$(folderID)).data;
      // Owner can always delete
      if (request.auth.uid == folder.ownerAthleteID) {
        return true;
      }
      // Coach can delete if they have permission
      if (request.auth.uid in folder.sharedWithCoachIDs) {
        return folder.permissions[request.auth.uid].canDelete == true;
      }
      return false;
    }
    
    // ============================================
    // User Profiles
    // ============================================
    
    match /users/{userID} {
      // Anyone authenticated can read any user profile (for displaying names)
      allow read: if isAuthenticated();
      
      // Users can only write their own profile
      allow create: if isAuthenticated() && isOwner(userID);
      
      // Users can update their own profile
      allow update: if isAuthenticated() && isOwner(userID);
      
      // Users cannot delete their profile (must be done through admin)
      allow delete: if false;
    }
    
    // ============================================
    // Shared Folders
    // ============================================
    
    match /sharedFolders/{folderID} {
      // Read: Owner or any coach with access
      allow read: if isAuthenticated() && canAccessFolder(folderID);
      
      // Create: Authenticated premium athletes only
      allow create: if isAuthenticated() 
                    && isAthlete()
                    && isPremium() 
                    && request.resource.data.ownerAthleteID == request.auth.uid;
      
      // Update: Only owner can modify folder settings
      allow update: if isAuthenticated() 
                    && resource.data.ownerAthleteID == request.auth.uid;
      
      // Delete: Only owner can delete
      allow delete: if isAuthenticated() 
                    && resource.data.ownerAthleteID == request.auth.uid;
    }
    
    // ============================================
    // Videos
    // ============================================
    
    match /videos/{videoID} {
      // Read: Anyone with folder access
      allow read: if isAuthenticated() 
                  && canAccessFolder(resource.data.sharedFolderID);
      
      // Create: Anyone with upload permission for the folder
      allow create: if isAuthenticated() 
                    && canUploadToFolder(request.resource.data.sharedFolderID)
                    && request.resource.data.uploadedBy == request.auth.uid;
      
      // Update: Uploader or folder owner can update metadata
      allow update: if isAuthenticated() 
                    && (request.auth.uid == resource.data.uploadedBy 
                        || canDeleteFromFolder(resource.data.sharedFolderID));
      
      // Delete: Uploader or someone with delete permission
      allow delete: if isAuthenticated() 
                    && (request.auth.uid == resource.data.uploadedBy 
                        || canDeleteFromFolder(resource.data.sharedFolderID));
    }
    
    // ============================================
    // Annotations (Video Comments)
    // ============================================
    
    match /videos/{videoID}/annotations/{annotationID} {
      // Read: Anyone with access to the parent video
      allow read: if isAuthenticated() 
                  && canAccessFolder(
                      get(/databases/$(database)/documents/videos/$(videoID)).data.sharedFolderID
                    );
      
      // Create: Anyone with folder access can comment
      allow create: if isAuthenticated() 
                    && request.resource.data.userID == request.auth.uid
                    && canAccessFolder(
                        get(/databases/$(database)/documents/videos/$(videoID)).data.sharedFolderID
                      );
      
      // Update: Only the comment author
      allow update: if isAuthenticated() 
                    && resource.data.userID == request.auth.uid;
      
      // Delete: Only the comment author or folder owner
      allow delete: if isAuthenticated() 
                    && (resource.data.userID == request.auth.uid
                        || canDeleteFromFolder(
                            get(/databases/$(database)/documents/videos/$(videoID)).data.sharedFolderID
                          ));
    }
    
    // ============================================
    // Invitations
    // ============================================
    
    match /invitations/{invitationID} {
      // Read: Athlete who sent it or coach it's addressed to
      allow read: if isAuthenticated() 
                  && (resource.data.athleteID == request.auth.uid 
                      || resource.data.coachEmail == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.email);
      
      // Create: Authenticated premium athletes only
      allow create: if isAuthenticated() 
                    && isAthlete()
                    && isPremium()
                    && request.resource.data.athleteID == request.auth.uid;
      
      // Update: Coach can accept/decline, athlete can resend
      allow update: if isAuthenticated();
      
      // Delete: Only the athlete who sent it
      allow delete: if isAuthenticated() 
                    && resource.data.athleteID == request.auth.uid;
    }
  }
}
```

### 3.3 Click **Publish** to activate the rules

---

## 🔒 Step 4: Add Firebase Storage Security Rules

### 4.1 Navigate to Storage Rules

1. In Firebase Console, go to **Storage**
2. Click the **Rules** tab
3. Replace with the following:

### 4.2 Storage Security Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // ============================================
    // Helper Functions
    // ============================================
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function canAccessFolder(folderID) {
      let folder = firestore.get(/databases/(default)/documents/sharedFolders/$(folderID)).data;
      return request.auth.uid == folder.ownerAthleteID 
          || request.auth.uid in folder.sharedWithCoachIDs;
    }
    
    function canUploadToFolder(folderID) {
      let folder = firestore.get(/databases/(default)/documents/sharedFolders/$(folderID)).data;
      // Owner can always upload
      if (request.auth.uid == folder.ownerAthleteID) {
        return true;
      }
      // Check coach permissions
      if (request.auth.uid in folder.sharedWithCoachIDs) {
        return folder.permissions[request.auth.uid].canUpload == true;
      }
      return false;
    }
    
    // ============================================
    // Shared Folder Videos
    // ============================================
    
    match /videos/sharedFolders/{folderID}/{allPaths=**} {
      // Read: Anyone with folder access
      allow read: if isAuthenticated() && canAccessFolder(folderID);
      
      // Write: Anyone with upload permission
      allow write: if isAuthenticated() && canUploadToFolder(folderID);
      
      // Delete: Folder owner only (for now)
      allow delete: if isAuthenticated() 
                    && firestore.get(/databases/(default)/documents/sharedFolders/$(folderID)).data.ownerAthleteID == request.auth.uid;
    }
    
    // ============================================
    // User Profile Images (Future)
    // ============================================
    
    match /users/{userID}/profile/{allPaths=**} {
      allow read: if isAuthenticated();
      allow write: if isAuthenticated() && request.auth.uid == userID;
    }
  }
}
```

### 4.3 Click **Publish**

---

## 🧪 Step 5: Test Role-Based Authentication

### 5.1 Create Test Accounts

Add this test function to `ComprehensiveAuthManager.swift` (temporary, for testing):

```swift
#if DEBUG
func createTestAccounts() async {
    print("🧪 Creating test accounts...")
    
    // Test Athlete Account
    do {
        try await Auth.auth().createUser(
            withEmail: "athlete@test.com",
            password: "TestPass123!"
        )
        if let user = Auth.auth().currentUser {
            try await createUserProfile(
                userID: user.uid,
                email: "athlete@test.com",
                displayName: "Test Athlete",
                role: .athlete
            )
            print("✅ Created test athlete account")
        }
    } catch {
        print("ℹ️ Test athlete already exists or error: \(error)")
    }
    
    // Test Coach Account
    do {
        try await Auth.auth().createUser(
            withEmail: "coach@test.com",
            password: "TestPass123!"
        )
        if let user = Auth.auth().currentUser {
            try await createUserProfile(
                userID: user.uid,
                email: "coach@test.com",
                displayName: "Test Coach",
                role: .coach
            )
            print("✅ Created test coach account")
        }
    } catch {
        print("ℹ️ Test coach already exists or error: \(error)")
    }
}
#endif
```

### 5.2 Run the App and Create Accounts

1. Build and run the app
2. Sign up as an athlete: `athlete@test.com` / `TestPass123!`
3. Sign out
4. Sign up as a coach: `coach@test.com` / `TestPass123!`
4. Verify that each role sees the correct onboarding flow

### 5.3 Verify in Firebase Console

1. Go to **Authentication** tab
2. Confirm both users appear
3. Go to **Firestore Database**
4. Check the `users` collection has both profiles with correct roles

---

## 🧪 Step 6: Test Firestore Permissions

### 6.1 Test Shared Folder Creation (Athlete)

Add this test to your app:

```swift
// In a View or test function
Task {
    do {
        // Sign in as athlete
        await authManager.signIn(email: "athlete@test.com", password: "TestPass123!")
        
        // Try to create a shared folder
        let folderID = try await FirestoreManager.shared.createSharedFolder(
            name: "Test Coach Folder",
            ownerAthleteID: authManager.userID!,
            permissions: [:]
        )
        
        print("✅ Successfully created folder: \(folderID)")
        
        // Fetch folders
        let folders = try await FirestoreManager.shared.fetchSharedFolders(
            forAthlete: authManager.userID!
        )
        print("✅ Fetched \(folders.count) folders")
        
    } catch {
        print("❌ Test failed: \(error)")
    }
}
```

### 6.2 Test Coach Access

```swift
Task {
    do {
        // First, as athlete, invite coach
        let invitationID = try await FirestoreManager.shared.createInvitation(
            athleteID: athleteUserID,
            athleteName: "Test Athlete",
            coachEmail: "coach@test.com",
            folderID: testFolderID,
            folderName: "Test Coach Folder"
        )
        print("✅ Created invitation: \(invitationID)")
        
        // Sign in as coach
        await authManager.signIn(email: "coach@test.com", password: "TestPass123!")
        
        // Check pending invitations
        let invitations = try await FirestoreManager.shared.fetchPendingInvitations(
            forEmail: "coach@test.com"
        )
        print("✅ Coach has \(invitations.count) pending invitations")
        
        // Accept invitation
        if let invitation = invitations.first {
            try await FirestoreManager.shared.acceptInvitation(
                invitationID: invitation.id!,
                coachID: authManager.userID!,
                permissions: .default
            )
            print("✅ Accepted invitation")
        }
        
        // Fetch coach's folders
        let coachFolders = try await FirestoreManager.shared.fetchSharedFolders(
            forCoach: authManager.userID!
        )
        print("✅ Coach has access to \(coachFolders.count) folders")
        
    } catch {
        print("❌ Test failed: \(error)")
    }
}
```

---

## ✅ Step 7: Verification Checklist

Before moving to Phase 2, verify all of these:

### Firebase Console
- [ ] Firestore Database is enabled
- [ ] Authentication is enabled (Email/Password)
- [ ] Storage is enabled
- [ ] Security rules are published for Firestore
- [ ] Security rules are published for Storage

### In App
- [ ] Athlete can sign up and see athlete onboarding
- [ ] Coach can sign up and see coach onboarding
- [ ] `ComprehensiveAuthManager.userRole` correctly identifies users
- [ ] User profiles are created in Firestore on signup
- [ ] FirestoreManager methods work without errors

### Firestore Tests
- [ ] Athlete can create shared folders
- [ ] Athlete can create invitations
- [ ] Coach can see pending invitations
- [ ] Coach can accept invitations and gain folder access
- [ ] Security rules prevent unauthorized access

---

## 🐛 Troubleshooting

### Issue: "Permission Denied" errors in Firestore

**Solution:**
1. Check that security rules are published
2. Verify user is authenticated: `Auth.auth().currentUser != nil`
3. Verify user profile has correct `role` field in Firestore
4. Check Firebase Console → Firestore → Rules → Rules Playground to test

### Issue: "Module not found" for Firebase imports

**Solution:**
1. Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)
2. Close and reopen Xcode
3. Verify Firebase packages are added in **Project → Package Dependencies**

### Issue: Firestore writes succeed but reads return empty

**Solution:**
1. Add indexes if needed (Firebase will show index creation links in console)
2. Check that you're querying the correct collection name
3. Use Firebase Console → Firestore → Data to manually inspect documents

### Issue: Auth state not persisting between app launches

**Solution:**
1. Check that Firebase is initialized in `AppDelegate` or `@main` struct:
```swift
import FirebaseCore

@main
struct PlayerPathApp: App {
    init() {
        FirebaseApp.configure()
    }
    // ...
}
```

---

## 📊 Success Metrics

You've successfully completed Phase 1 when:

✅ Both athlete and coach users can sign up  
✅ User profiles are correctly stored in Firestore with roles  
✅ Firestore security rules block unauthorized access  
✅ You can create shared folders via `FirestoreManager`  
✅ Invitations system works end-to-end  
✅ No permission errors in console logs  

---

## 🎯 Next Steps: Phase 2

Once Phase 1 is complete, you're ready for **Phase 2: Shared Folder System**, which includes:

- Building the "Create Coach Folder" UI
- Athlete folder management screen
- Coach dashboard showing all shared folders
- Invitation acceptance flow in the app
- Premium feature gating

**Estimated Time:** Phase 1 should take 1-2 days to complete and test thoroughly.

---

## 📚 Resources

- [Firebase iOS Setup Guide](https://firebase.google.com/docs/ios/setup)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase Storage Security](https://firebase.google.com/docs/storage/security)
- [Swift Concurrency with Firebase](https://firebase.google.com/docs/ios/swift-async-await)

---

**Questions or Issues?** 
Check the Troubleshooting section above or review the Firebase Console logs for specific error messages.
