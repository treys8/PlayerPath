# Firebase Setup Guide for Coach Sharing Feature

## 📋 Prerequisites

- [x] Firebase project exists (you have this)
- [x] Firebase iOS SDK installed (v12.4.0 confirmed)
- [x] GoogleService-Info.plist in project
- [x] Firebase Auth enabled

## 🚀 Quick Setup Steps

### Step 1: Enable Firestore Database

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your **PlayerPath** project
3. Click **Firestore Database** in left sidebar
4. Click **Create database**
5. Choose **Start in production mode** (we'll add rules next)
6. Select a location (us-central1 recommended for US)
7. Wait for provisioning (~30 seconds)

### Step 2: Deploy Firestore Security Rules

1. In Firebase Console, go to **Firestore Database → Rules**
2. **Copy the entire contents** of `/repo/firestore.rules`
3. **Paste** into the rules editor
4. Click **Publish**
5. Verify: Should show "Published" with timestamp

**Alternative (using Firebase CLI):**
```bash
cd /path/to/your/project
firebase deploy --only firestore:rules
```

### Step 3: Enable Firebase Storage

1. In Firebase Console, go to **Storage** in left sidebar
2. Click **Get started**
3. Choose **Start in production mode**
4. Select same location as Firestore (us-central1)
5. Click **Done**

### Step 4: Deploy Storage Security Rules

1. In Firebase Console, go to **Storage → Rules**
2. **Copy the entire contents** of `/repo/storage.rules`
3. **Paste** into the rules editor
4. Click **Publish**

**Alternative (using Firebase CLI):**
```bash
firebase deploy --only storage:rules
```

### Step 5: Verify Xcode Build

1. **Open your project in Xcode**
2. **Build** (Cmd+B) to ensure no errors
3. Check for Firebase import errors:
   - `FirestoreManager.swift` should compile
   - `SharedFolderManager.swift` should compile
   - No "Cannot find 'Firestore' in scope" errors

### Step 6: Test Firestore Connection

Run this in your app to verify Firestore works:

```swift
// Add to a test view or button action
Task {
    do {
        // Try to create a test document
        let testData: [String: Any] = [
            "test": true,
            "timestamp": Date()
        ]
        
        try await Firestore.firestore()
            .collection("_test_")
            .document("connection_test")
            .setData(testData)
        
        print("✅ Firestore connection successful!")
        
        // Clean up
        try await Firestore.firestore()
            .collection("_test_")
            .document("connection_test")
            .delete()
        
    } catch {
        print("❌ Firestore connection failed: \(error)")
    }
}
```

### Step 7: Test Storage Connection

Run this to verify Storage works:

```swift
// Add to a test view or button action
Task {
    do {
        let storageRef = Storage.storage().reference()
        let testRef = storageRef.child("_test_/connection_test.txt")
        
        let testData = "Hello from PlayerPath!".data(using: .utf8)!
        
        _ = try await testRef.putDataAsync(testData)
        print("✅ Storage upload successful!")
        
        // Clean up
        try await testRef.delete()
        
    } catch {
        print("❌ Storage connection failed: \(error)")
    }
}
```

---

## 🔍 Verify Installation

### Checklist

- [ ] Firebase Console shows Firestore database is active
- [ ] Firebase Console shows Storage bucket is created
- [ ] Firestore rules show as "Published" (not "Not published")
- [ ] Storage rules show as "Published"
- [ ] Xcode build succeeds with no Firebase import errors
- [ ] Test Firestore write succeeds (from Step 6)
- [ ] Test Storage upload succeeds (from Step 7)

---

## 🧪 Manual Testing

### Test 1: Create User Profile

```swift
let firestoreManager = FirestoreManager.shared

// Sign up a test user first (in your app)
// Then create their profile:

try await firestoreManager.updateUserProfile(
    userID: Auth.auth().currentUser!.uid,
    email: "test@example.com",
    role: .athlete,
    profileData: [
        "displayName": "Test Athlete",
        "isPremium": true
    ]
)

// Verify in Firebase Console → Firestore → users collection
```

### Test 2: Create Shared Folder

```swift
let sharedFolderManager = SharedFolderManager.shared

let folderID = try await sharedFolderManager.createFolder(
    name: "Test Coach Folder",
    forAthlete: Auth.auth().currentUser!.uid,
    isPremium: true
)

print("Created folder: \(folderID)")

// Verify in Firebase Console → Firestore → sharedFolders collection
```

### Test 3: Send Invitation

```swift
try await sharedFolderManager.inviteCoachToFolder(
    coachEmail: "coach@example.com",
    folderID: folderID,
    athleteID: Auth.auth().currentUser!.uid,
    athleteName: "Test Athlete",
    folderName: "Test Coach Folder",
    permissions: .default
)

// Verify in Firebase Console → Firestore → invitations collection
```

---

## 📊 Monitoring & Debugging

### Firebase Console Views

**Firestore Data:**
- URL: `https://console.firebase.google.com/project/YOUR_PROJECT/firestore/data`
- Check: users, sharedFolders, videos, invitations collections

**Storage Files:**
- URL: `https://console.firebase.google.com/project/YOUR_PROJECT/storage/files`
- Check: sharedFolders folder appears after first upload

**Usage Stats:**
- Firestore: `https://console.firebase.google.com/project/YOUR_PROJECT/firestore/usage`
- Storage: `https://console.firebase.google.com/project/YOUR_PROJECT/storage/usage`

### Common Issues

#### Issue: "Permission denied" when writing to Firestore
**Solution:** Verify rules are published. Check user is authenticated (`Auth.auth().currentUser != nil`)

#### Issue: "Firebase/Firestore module not found"
**Solution:** 
1. Verify Firebase SDK in Xcode → Package Dependencies
2. Check target has Firestore linked: Target → Build Phases → Link Binary

#### Issue: "Storage upload fails with 403"
**Solution:** Verify storage rules are published. Check user is authenticated.

#### Issue: "Cannot create folder, premium required"
**Solution:** Update user's `isPremium` field in Firestore users collection

---

## 💰 Cost Estimation

### Firestore Pricing (Free Tier)

**Generous free quota:**
- **Reads:** 50,000/day
- **Writes:** 20,000/day
- **Deletes:** 20,000/day
- **Storage:** 1 GB

**Estimated usage (100 active users):**
- Folder creation: ~10/day (200 writes)
- Video uploads: ~50/day (100 writes)
- Annotations: ~200/day (400 writes)
- Reads: ~1,000/day (viewing videos, comments)

**Verdict:** Should stay in free tier for MVP/beta

### Storage Pricing (Free Tier)

**Free quota:**
- **Storage:** 5 GB
- **Downloads:** 1 GB/day
- **Uploads:** Unlimited

**Estimated usage:**
- Average video: 100 MB
- 50 videos = 5 GB (at free tier limit)

**Verdict:** Will need paid plan once you have >50 videos

**Cost after free tier:** ~$0.026/GB/month
- Example: 100 GB = $2.60/month

---

## 🎯 Next Steps After Setup

1. **Test the connection** (Steps 6-7 above)
2. **Create a test athlete account**
3. **Create a test shared folder**
4. **Move to Phase 2** - Build the UI for folder management

---

## 📚 Additional Resources

**Firebase Documentation:**
- [Firestore Quickstart](https://firebase.google.com/docs/firestore/quickstart)
- [Storage Quickstart](https://firebase.google.com/docs/storage/ios/start)
- [Security Rules](https://firebase.google.com/docs/rules)

**Debugging Tools:**
- [Firestore Rules Simulator](https://firebase.google.com/docs/rules/simulator)
- [Firebase CLI](https://firebase.google.com/docs/cli)

---

## ✅ Setup Complete Checklist

Before moving to Phase 2, confirm:

- [ ] Firestore database created
- [ ] Firestore rules deployed
- [ ] Storage bucket created
- [ ] Storage rules deployed
- [ ] Xcode build succeeds
- [ ] Test Firestore write works
- [ ] Test Storage upload works
- [ ] Can see data in Firebase Console
- [ ] Security rules prevent unauthorized access (test with logged-out user)

**Once all checked, you're ready for Phase 2!** 🚀
