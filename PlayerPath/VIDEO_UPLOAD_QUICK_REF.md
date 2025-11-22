# Video Upload & Storage - Quick Reference

**Last Updated:** November 22, 2025

---

## 🚀 Quick Start

### Upload a Video

```swift
// 1. Upload video with progress
let storageURL = try await VideoCloudManager.shared.uploadVideo(
    localURL: videoURL,
    fileName: "game_opponent_2025-11-22.mov",
    folderID: "folder123",
    progressHandler: { progress in
        print("Upload: \(Int(progress * 100))%")
    }
)

// 2. Upload thumbnail (optional but recommended)
let thumbnailURL = try await VideoCloudManager.shared.uploadThumbnail(
    thumbnailURL: thumbnailFileURL,
    videoFileName: "game_opponent_2025-11-22.mov",
    folderID: "folder123"
)

// 3. Save metadata to Firestore
try await FirestoreManager.shared.createVideoMetadata(
    folderID: "folder123",
    metadata: [
        "fileName": "game_opponent_2025-11-22.mov",
        "firebaseStorageURL": storageURL,
        "thumbnailURL": thumbnailURL,
        "uploadedBy": userID,
        "uploadedByName": userName,
        "sharedFolderID": "folder123",
        "isHighlight": false,
        "createdAt": Date()
    ]
)
```

### Generate Thumbnail

```swift
let result = await VideoFileManager.generateThumbnail(from: videoURL)

switch result {
case .success(let localPath):
    print("Thumbnail saved to: \(localPath)")
    // Upload thumbnail
case .failure(let error):
    print("Thumbnail generation failed: \(error)")
}
```

### Get Secure Download URL

```swift
// For video playback
let videoURL = try await VideoCloudManager.shared.getSecureDownloadURL(
    fileName: "game_opponent_2025-11-22.mov",
    folderID: "folder123"
)

// For thumbnail display
let thumbnailURL = try await VideoCloudManager.shared.getSecureThumbnailURL(
    videoFileName: "game_opponent_2025-11-22.mov",
    folderID: "folder123"
)
```

---

## 📁 Storage Paths

### Firebase Storage
```
shared_folders/
  └── {folderID}/
      ├── game_opponent_2025-11-22.mov          ← Videos
      ├── practice_2025-11-21.mov
      └── thumbnails/                            ← Thumbnails
          ├── game_opponent_2025-11-22_thumbnail.jpg
          └── practice_2025-11-21_thumbnail.jpg
```

### Firestore
```
/sharedFolders/{folderID}
  - name, ownerAthleteID, permissions, videoCount

/videos/{videoID}
  - fileName
  - firebaseStorageURL
  - thumbnailURL
  - uploadedBy, uploadedByName
  - sharedFolderID
  - isHighlight
  - videoType: "game" | "practice"
  - gameOpponent, gameDate, practiceDate
  - notes
  - createdAt
```

---

## 🔒 Security

### URL Security Model

Firebase Storage URLs are secured with **tokens**:

```
https://firebasestorage.googleapis.com/.../video.mov?token=abc123xyz
                                                    ↑ Security token
```

- ✅ Token validates against Storage Rules on EVERY access
- ✅ Even if URL is shared, unauthorized users can't access
- ✅ Permissions checked in real-time
- ✅ Instant revocation when coach is removed from folder

### Storage Rules

```javascript
// Only folder owner and shared coaches can access videos
match /shared_folders/{folderID}/{fileName} {
  allow read: if isOwner(folderID) || isSharedCoach(folderID);
  allow write: if isOwner(folderID) || canUpload(folderID);
  allow delete: if isOwner(folderID);
}
```

---

## 📊 File Specifications

### Video Files
- **Max size:** 500MB
- **Min size:** 1KB
- **Max duration:** 10 minutes
- **Min duration:** 1 second
- **Formats:** .mov, .mp4, .MOV, .MP4
- **Content type:** `video/quicktime`

### Thumbnail Images
- **Size:** 160x120 pixels (default)
- **Format:** JPEG
- **Compression:** 0.8 quality
- **File size:** ~10-20KB per thumbnail
- **Content type:** `image/jpeg`
- **Cache control:** `public, max-age=31536000` (1 year)

---

## 🎯 Error Codes

| Error | Meaning | Solution |
|-------|---------|----------|
| `VideoCloudError.uploadFailed` | Network or Firebase error | Retry upload |
| `VideoCloudError.invalidURL` | Could not generate download URL | Check file exists |
| `VideoCloudError.storageQuotaExceeded` | Out of storage space | Upgrade plan |
| `ValidationError.fileTooLarge` | Video > 500MB | Compress video |
| `ValidationError.durationTooLong` | Video > 10 minutes | Trim video |

---

## 💡 Best Practices

### DO ✅
- Generate and upload thumbnails for all videos
- Use progress handlers to show upload status
- Clean up local files after successful upload
- Handle thumbnail failures gracefully (continue with video)
- Validate videos before uploading
- Save metadata to Firestore after upload completes

### DON'T ❌
- Upload videos > 500MB
- Upload without progress indication
- Assume thumbnails will always succeed
- Skip error handling
- Upload to wrong storage paths
- Forget to clean up temporary files

---

## 🧪 Testing Commands

### Upload Test
```swift
Task {
    do {
        let url = URL(fileURLWithPath: "path/to/test-video.mov")
        
        let storageURL = try await VideoCloudManager.shared.uploadVideo(
            localURL: url,
            fileName: "test-video.mov",
            folderID: "test-folder",
            progressHandler: { print("Progress: \($0)") }
        )
        
        print("✅ Upload successful: \(storageURL)")
    } catch {
        print("❌ Upload failed: \(error)")
    }
}
```

### Thumbnail Test
```swift
Task {
    let result = await VideoFileManager.generateThumbnail(
        from: videoURL,
        at: CMTime(seconds: 1, preferredTimescale: 1),
        size: CGSize(width: 160, height: 120)
    )
    
    switch result {
    case .success(let path):
        print("✅ Thumbnail: \(path)")
    case .failure(let error):
        print("❌ Failed: \(error)")
    }
}
```

### Security Test
```swift
// Test unauthorized access (should fail)
Task {
    do {
        // Sign out or use different user
        let url = try await VideoCloudManager.shared.getSecureDownloadURL(
            fileName: "unauthorized-video.mov",
            folderID: "not-shared-with-me"
        )
        print("❌ Security issue: unauthorized access succeeded")
    } catch {
        print("✅ Security working: unauthorized access blocked")
    }
}
```

---

## 📚 Related Files

- **`VideoCloudManager.swift`** - Upload/download methods
- **`VideoFileManager.swift`** - Thumbnail generation & validation
- **`CoachVideoUploadView.swift`** - Upload UI
- **`FirestoreManager.swift`** - Metadata management
- **`storage.rules`** - Firebase Storage security
- **`firestore.rules`** - Firestore security
- **`PHASE3_VIDEO_UPLOAD_COMPLETE.md`** - Full implementation docs

---

## 🆘 Common Issues

### "Permission denied" when accessing video
**Fix:** Deploy storage rules: `firebase deploy --only storage:rules`

### Thumbnail generation fails
**Fix:** Check video format and duration. Some videos may not support thumbnail extraction.

### Upload progress not updating
**Fix:** Ensure `@Published` properties and `@MainActor` are used correctly.

### Video URL returns 404
**Fix:** Verify file was uploaded successfully and path matches exactly.

---

## 🔗 Quick Links

- Firebase Console: https://console.firebase.google.com
- Storage Browser: Console → Storage → Files
- Firestore Browser: Console → Firestore Database
- Storage Rules: Console → Storage → Rules
- Firestore Rules: Console → Firestore → Rules

---

**Status:** ✅ Production Ready  
**Version:** 1.0  
**Phase:** 3 Complete
