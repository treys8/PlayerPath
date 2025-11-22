# Firebase Architecture Diagram

**Project:** PlayerPath Baseball App  
**Purpose:** Visual guide to data flow and security rules

---

## 🏗️ Firestore Collections Structure

```
📦 Firestore Database
│
├── 📁 users/{userID}
│   ├── email: String
│   ├── role: "athlete" | "coach"
│   ├── isPremium: Boolean
│   ├── displayName: String
│   ├── createdAt: Timestamp
│   └── updatedAt: Timestamp
│
├── 📁 sharedFolders/{folderID}
│   ├── name: String
│   ├── ownerAthleteID: String
│   ├── sharedWithCoachIDs: [String]
│   ├── permissions: {
│   │   coachID1: {
│   │       canUpload: Boolean,
│   │       canComment: Boolean,
│   │       canDelete: Boolean
│   │   }
│   │}
│   ├── videoCount: Number
│   ├── createdAt: Timestamp
│   └── updatedAt: Timestamp
│
├── 📁 videos/{videoID}
│   ├── fileName: String
│   ├── firebaseStorageURL: String
│   ├── thumbnailURL: String?
│   ├── uploadedBy: String (userID)
│   ├── uploadedByName: String
│   ├── sharedFolderID: String
│   ├── fileSize: Number
│   ├── duration: Number?
│   ├── isHighlight: Boolean
│   ├── createdAt: Timestamp
│   │
│   └── 📁 annotations (subcollection)
│       ├── {annotationID}
│       │   ├── userID: String
│       │   ├── userName: String
│       │   ├── timestamp: Number (seconds)
│       │   ├── text: String
│       │   ├── isCoachComment: Boolean
│       │   └── createdAt: Timestamp
│       └── ...
│
└── 📁 invitations/{invitationID}
    ├── athleteID: String
    ├── athleteName: String
    ├── coachEmail: String
    ├── folderID: String
    ├── folderName: String
    ├── status: "pending" | "accepted" | "declined"
    ├── sentAt: Timestamp
    └── expiresAt: Timestamp
```

---

## 📦 Firebase Storage Structure

```
📦 Firebase Storage
│
└── videos/
    └── sharedFolders/
        ├── {folderID}/
        │   ├── {videoID}.mov
        │   ├── {videoID}_thumbnail.jpg
        │   ├── {videoID2}.mov
        │   └── {videoID2}_thumbnail.jpg
        └── {folderID2}/
            └── ...
```

---

## 🔒 Security Rules Logic

### Firestore Rules Flow

```
                    ┌─────────────────────┐
                    │   Request Arrives   │
                    └──────────┬──────────┘
                               ↓
                    ┌──────────────────────┐
                    │  Is User Authenticated? │
                    └──────────┬──────────┘
                               ↓ Yes
                    ┌──────────────────────┐
                    │  Check User Role     │
                    │  from /users/{uid}   │
                    └──────────┬──────────┘
                               ↓
        ┌──────────────────────┴──────────────────────┐
        ↓                                              ↓
┌───────────────┐                              ┌──────────────┐
│  Role: Athlete│                              │ Role: Coach  │
└───────┬───────┘                              └──────┬───────┘
        ↓                                              ↓
  ┌────────────────┐                          ┌─────────────────┐
  │ Can Create     │                          │ Cannot Create   │
  │ Shared Folders │                          │ Shared Folders  │
  │ (if Premium)   │                          │                 │
  └────────────────┘                          └─────────────────┘
        ↓                                              ↓
  ┌────────────────┐                          ┌─────────────────┐
  │ Can Manage     │                          │ Can View Shared │
  │ Own Folders    │                          │ Folders Only    │
  └────────────────┘                          └─────────────────┘
```

### Shared Folder Access Check

```
Request to Access Folder
        ↓
┌──────────────────────────────┐
│ Is user ownerAthleteID?      │
└────────┬─────────────────────┘
         ↓ No
┌──────────────────────────────┐
│ Is user in sharedWithCoachIDs?│
└────────┬─────────────────────┘
         ↓ Yes
┌──────────────────────────────┐
│ ✅ Access Granted            │
└──────────────────────────────┘
```

### Video Upload Permission Check

```
Request to Upload Video
        ↓
┌──────────────────────────────┐
│ Get Folder Document          │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Is user folder owner?        │
└────────┬─────────────────────┘
         ↓ No
┌──────────────────────────────┐
│ Is user in sharedWithCoachIDs?│
└────────┬─────────────────────┘
         ↓ Yes
┌──────────────────────────────┐
│ Check permissions.canUpload  │
└────────┬─────────────────────┘
         ↓ true
┌──────────────────────────────┐
│ ✅ Upload Allowed            │
└──────────────────────────────┘
```

---

## 🔄 User Flows

### Flow 1: Athlete Creates Shared Folder

```
Athlete Opens App
        ↓
┌──────────────────────────────┐
│ Navigates to Profile/Coaches │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Taps "Create Coach Folder"   │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Check: isPremium == true?    │
└────────┬─────────────────────┘
         ↓ Yes
┌──────────────────────────────┐
│ Enters Folder Name           │
│ e.g., "Coach Smith Folder"   │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Sets Permissions:            │
│ ☑ Can Upload                 │
│ ☑ Can Comment                │
│ ☐ Can Delete                 │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Enters Coach Email           │
│ coach@example.com            │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ FirestoreManager             │
│ .createSharedFolder()        │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ FirestoreManager             │
│ .createInvitation()          │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ ✅ Invitation Sent           │
│ (Email notification optional)│
└──────────────────────────────┘
```

### Flow 2: Coach Accepts Invitation

```
Coach Opens App (First Time)
        ↓
┌──────────────────────────────┐
│ Signs Up with Email          │
│ coach@example.com            │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ ComprehensiveAuthManager     │
│ .signUpAsCoach()             │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ User Profile Created         │
│ role: "coach"                │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Sees CoachOnboardingFlow     │
│ "Welcome, Coach!"            │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ SharedFolderManager          │
│ .checkPendingInvitations()   │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Shows Pending Invitations    │
│ "Test Athlete invited you"   │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Coach Taps "Accept"          │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ FirestoreManager             │
│ .acceptInvitation()          │
│ ↓ calls                      │
│ .addCoachToFolder()          │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Coach Added to:              │
│ folder.sharedWithCoachIDs    │
│ folder.permissions[coachID]  │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ ✅ Coach Can Now Access      │
│ Folder & Videos              │
└──────────────────────────────┘
```

### Flow 3: Coach Uploads Video to Shared Folder

```
Coach Opens Shared Folder
        ↓
┌──────────────────────────────┐
│ Taps "Upload Video"          │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Records or Selects Video     │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ VideoCloudManager            │
│ .uploadVideo()               │
│ → Firebase Storage           │
│   /videos/sharedFolders/     │
│   {folderID}/{videoID}.mov   │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Gets Download URL            │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ FirestoreManager             │
│ .uploadVideoMetadata()       │
│ → Creates /videos/{videoID}  │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Security Rule Checks:        │
│ 1. canUploadToFolder()?      │
│ 2. uploadedBy == coachID?    │
└────────┬─────────────────────┘
         ↓ Pass
┌──────────────────────────────┐
│ ✅ Video Saved               │
│ Athlete Gets Notification    │
└──────────────────────────────┘
```

---

## 🔐 Permission Matrix

| Action | Athlete (Owner) | Coach (w/ Upload) | Coach (View Only) |
|--------|----------------|-------------------|-------------------|
| View Folder | ✅ | ✅ | ✅ |
| Upload Video | ✅ | ✅ | ❌ |
| Delete Own Video | ✅ | ✅ | ✅ |
| Delete Other's Video | ✅ | ❌* | ❌ |
| Add Comment | ✅ | ✅ | ✅ |
| Delete Own Comment | ✅ | ✅ | ✅ |
| Delete Other's Comment | ✅ | ❌ | ❌ |
| Modify Folder Settings | ✅ | ❌ | ❌ |
| Delete Folder | ✅ | ❌ | ❌ |

*Unless `canDelete` permission is granted

---

## 📊 Data Relationships

```
User (Athlete)
    ↓ owns
SharedFolder
    ↓ shared with
User (Coach) ←─┐
    ↓          │
    ↓ has      │
Permissions    │
    ↓          │
    ↓ uploads  │
Video          │
    ↓          │
    ↓ belongs to
SharedFolder ──┘
    ↓ contains
Annotations
```

---

## 🧪 Testing Scenarios

### Test 1: Unauthorized Access
```
1. Create shared folder as Athlete A
2. Invite Coach X
3. Try to access folder as Coach Y (not invited)
Expected: ❌ Permission Denied
```

### Test 2: Upload Permission
```
1. Create shared folder as Athlete A
2. Invite Coach X with canUpload: false
3. Coach X tries to upload video
Expected: ❌ Permission Denied
```

### Test 3: Delete Permission
```
1. Coach X uploads video to shared folder
2. Coach Y tries to delete Coach X's video
Expected: ❌ Permission Denied
```

### Test 4: Owner Override
```
1. Coach X uploads video to shared folder
2. Athlete A (owner) deletes Coach X's video
Expected: ✅ Success
```

---

## 🔍 Firestore Indexes

These indexes may be auto-created by Firebase:

1. **sharedFolders**
   - `ownerAthleteID` + `createdAt` (descending)
   - `sharedWithCoachIDs` (array) + `updatedAt` (descending)

2. **videos**
   - `sharedFolderID` + `createdAt` (descending)
   - `uploadedBy` + `createdAt` (descending)

3. **invitations**
   - `coachEmail` + `status`
   - `athleteID` + `status`

Firebase will prompt you to create these if needed.

---

## 📱 Real-Time Updates

### Annotations Listener
```swift
// In SwiftUI View
.onAppear {
    annotationsListener = FirestoreManager.shared.listenToAnnotations(
        videoID: videoID
    ) { annotations in
        self.annotations = annotations
    }
}
.onDisappear {
    annotationsListener?.remove()
}
```

This enables real-time comments while watching videos together!

---

## 🎯 Summary

- **4 Collections:** users, sharedFolders, videos, invitations
- **1 Subcollection:** videos/{id}/annotations
- **2 User Roles:** athlete, coach
- **3 Permission Levels:** canUpload, canComment, canDelete
- **Security Rules:** 200+ lines protecting data
- **Storage Rules:** Protected file access by folder

---

**Ready to implement?** Start with `PHASE_1_QUICK_START.md`
