# Phase 1: Quick Start Checklist

**Goal:** Get Firebase Foundation up and running in 30 minutes

---

## ⚡ Quick Setup (Follow in Order)

### 1. Add Firebase SDK (5 minutes)

**In Xcode:**
1. **File → Add Package Dependencies...**
2. Paste: `https://github.com/firebase/firebase-ios-sdk`
3. Select packages:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore  
   - ✅ FirebaseStorage
4. Click **Add Package**

---

### 2. Configure Firebase Console (10 minutes)

**Go to:** [Firebase Console](https://console.firebase.google.com/)

#### Enable Firestore:
1. **Build → Firestore Database**
2. **Create database**
3. Choose **Production mode**
4. Select region: `us-central1` (or closest to you)

#### Enable Authentication:
1. **Build → Authentication**
2. **Get started**
3. Enable **Email/Password** provider

#### Enable Storage:
1. **Build → Storage**
2. **Get started**
3. Choose **Production mode** (same region as Firestore)

---

### 3. Add Security Rules (10 minutes)

#### Firestore Rules:

1. **Firestore Database → Rules tab**
2. Copy from: `PHASE_1_IMPLEMENTATION_GUIDE.md` (Section 3.2)
3. Click **Publish**

#### Storage Rules:

1. **Storage → Rules tab**
2. Copy from: `PHASE_1_IMPLEMENTATION_GUIDE.md` (Section 4.2)
3. Click **Publish**

---

### 4. Test the Setup (5 minutes)

**In your app:**

1. Build and run
2. Sign up as athlete: `test-athlete@example.com`
3. Sign out
4. Sign up as coach: `test-coach@example.com`
5. Verify in **Firebase Console → Authentication** that both users exist
6. Verify in **Firestore Database → users collection** that profiles have correct `role` field

---

## ✅ Verification

Phase 1 is complete when:

- [ ] Firebase packages installed (no import errors)
- [ ] Firestore, Auth, and Storage enabled in Firebase Console
- [ ] Security rules published (both Firestore and Storage)
- [ ] Test athlete account created with `role: "athlete"`
- [ ] Test coach account created with `role: "coach"`
- [ ] Both users see correct onboarding screens
- [ ] User documents visible in Firestore Console

---

## 🧪 Quick Test Code

Add this to any View to test Firestore:

```swift
Button("Test Firestore") {
    Task {
        do {
            guard let userID = authManager.userID else {
                print("❌ Not signed in")
                return
            }
            
            // Test creating a folder
            let folderID = try await FirestoreManager.shared.createSharedFolder(
                name: "My First Coach Folder",
                ownerAthleteID: userID,
                permissions: [:]
            )
            print("✅ Created folder: \(folderID)")
            
            // Test fetching folders
            let folders = try await FirestoreManager.shared.fetchSharedFolders(
                forAthlete: userID
            )
            print("✅ Found \(folders.count) folders")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

---

## 🐛 Common Issues

### "Module not found: FirebaseFirestore"
**Fix:** Clean build folder (Cmd+Shift+K), restart Xcode

### "Permission denied" in Firestore
**Fix:** Verify security rules are published, check user is signed in

### User profile not created
**Fix:** Check `createUserProfile()` is called in `signUp()` method

---

## 🎯 What's Working After Phase 1

✅ Firebase Authentication with roles  
✅ Firestore database ready for shared data  
✅ Security rules protecting user data  
✅ User profiles stored in Firestore  
✅ Athlete/Coach onboarding flows  
✅ Foundation ready for Phase 2 (UI implementation)

---

## 📊 Firebase Console URLs (Bookmark These)

- **Authentication:** `https://console.firebase.google.com/project/YOUR_PROJECT/authentication/users`
- **Firestore:** `https://console.firebase.google.com/project/YOUR_PROJECT/firestore/data`
- **Storage:** `https://console.firebase.google.com/project/YOUR_PROJECT/storage`

Replace `YOUR_PROJECT` with your Firebase project ID.

---

**Ready for Phase 2?** See `PHASE_2_IMPLEMENTATION_GUIDE.md` (coming soon) for building the shared folder UI.
