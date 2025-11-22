# 🎬 Video Upload & Storage - Quick Reference

## 📥 Upload a Video with Thumbnail

```swift
// In your upload view model
func uploadVideo(uploaderID: String, uploaderName: String) async {
    guard let videoURL = selectedVideoURL,
          let folderID = folder.id else { return }
    
    do {
        let fileName = "video_\(Date().timeIntervalSince1970).mov"
        
        // 1. Generate thumbnail
        let thumbnailResult = await VideoFileManager.generateThumbnail(from: videoURL)
        
        var thumbnailURL: String?
        if case .success(let localPath) = thumbnailResult {
            // 2. Upload thumbnail
            thumbnailURL = try await VideoCloudManager.shared.uploadThumbnail(
                thumbnailURL: URL(fileURLWithPath: localPath),
                videoFileName: fileName,
                folderID: folderID
            )
        }
        
        // 3. Upload video
        let videoURL = try await VideoCloudManager.shared.uploadVideo(
            localURL: videoURL,
            fileName: fileName,
            folderID: folderID,
            progressHandler: { progress in
                print("Progress: \(Int(progress * 100))%")
            }
        )
        
        // 4. Save metadata to Firestore
        let metadata: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": videoURL,
            "thumbnailURL": thumbnailURL as Any,
            "uploadedBy": uploaderID,
            "createdAt": Date()
        ]
        
        try await FirestoreManager.shared.createVideoMetadata(
            folderID: folderID,
            metadata: metadata
        )
        
        print("✅ Upload complete!")
        
    } catch {
        print("❌ Upload failed: \(error)")
    }
}
```

## 🔐 Get Secure Video URL

```swift
// Get a secure, time-limited URL for video playback
Task {
    do {
        let url = try await SecureURLManager.shared.getSecureVideoURL(
            fileName: "video.mov",
            folderID: "folder123",
            expirationHours: 24  // URL valid for 24 hours
        )
        
        // Use the URL for playback
        let player = AVPlayer(url: URL(string: url)!)
        
    } catch {
        print("Error: \(error)")
    }
}
```

## 🖼️ Get Secure Thumbnail URL

```swift
// Get a secure URL for thumbnail display
Task {
    do {
        let url = try await SecureURLManager.shared.getSecureThumbnailURL(
            videoFileName: "video.mov",
            folderID: "folder123",
            expirationHours: 168  // 7 days for thumbnails
        )
        
        // Use AsyncImage or other image loader
        AsyncImage(url: URL(string: url))
        
    } catch {
        print("Error: \(error)")
    }
}
```

## 📦 Batch Get Secure URLs

```swift
// Get multiple URLs efficiently
Task {
    do {
        let urls = try await SecureURLManager.shared.getBatchSecureVideoURLs(
            fileNames: ["video1.mov", "video2.mov", "video3.mov"],
            folderID: "folder123"
        )
        
        for (fileName, url) in urls {
            print("\(fileName): \(url)")
        }
        
    } catch {
        print("Error: \(error)")
    }
}
```

## 🎨 Generate Thumbnail Only

```swift
// Generate thumbnail without uploading
Task {
    let result = await VideoFileManager.generateThumbnail(
        from: videoURL,
        at: CMTime(seconds: 1, preferredTimescale: 1),  // 1 second into video
        size: CGSize(width: 160, height: 120)
    )
    
    switch result {
    case .success(let localPath):
        print("Thumbnail saved to: \(localPath)")
        
        // Load and display
        if let image = UIImage(contentsOfFile: localPath) {
            // Use the image
        }
        
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

## 🗑️ Clear URL Cache

```swift
// Clear all cached URLs
SecureURLManager.shared.clearCache()

// Or clean only expired URLs
SecureURLManager.shared.cleanExpiredURLs()
```

## 🔧 Storage Paths

```
Firebase Storage Structure:

shared_folders/
  └── {folderID}/
      ├── video1.mov              ← Videos
      ├── video2.mov
      └── thumbnails/             ← Thumbnails
          ├── video1_thumbnail.jpg
          └── video2_thumbnail.jpg
```

## 📊 Firestore Metadata

```swift
// Video metadata in Firestore
{
    "fileName": "game_opponent_2025-11-22.mov",
    "firebaseStorageURL": "https://firebasestorage.googleapis.com/...",
    "thumbnailURL": "https://firebasestorage.googleapis.com/.../thumbnails/...",
    "uploadedBy": "user123",
    "uploadedByName": "Coach John",
    "sharedFolderID": "folder123",
    "isHighlight": false,
    "videoType": "game",
    "gameOpponent": "Tigers",
    "gameDate": "2025-11-22T00:00:00Z",
    "createdAt": "2025-11-22T14:30:00Z"
}
```

## ⚡️ Performance Tips

1. **Use batch URL generation** for lists:
   ```swift
   // ❌ Bad: Multiple function calls
   for fileName in fileNames {
       let url = try await getSecureVideoURL(fileName: fileName, ...)
   }
   
   // ✅ Good: Single batch call
   let urls = try await getBatchSecureVideoURLs(fileNames: fileNames, ...)
   ```

2. **Cache URLs** are automatic - don't call repeatedly:
   ```swift
   // URLs are cached automatically for their expiration time
   let url1 = try await getSecureVideoURL(...)  // Fetches from Cloud Function
   let url2 = try await getSecureVideoURL(...)  // Returns from cache
   ```

3. **Clean expired URLs** periodically:
   ```swift
   // In your app's lifecycle
   .onAppear {
       SecureURLManager.shared.cleanExpiredURLs()
   }
   ```

## 🚨 Error Handling

```swift
do {
    let url = try await SecureURLManager.shared.getSecureVideoURL(...)
} catch SecureURLError.invalidResponse {
    // Handle invalid Cloud Function response
} catch SecureURLError.functionCallFailed(let error) {
    // Handle network or Cloud Function errors
} catch SecureURLError.functionNotDeployed {
    // Cloud Functions not deployed yet
} catch {
    // Handle other errors
}
```

## 🔒 Security Rules Summary

| Path | Owner | Coach (shared) | Coach (upload permission) |
|------|-------|----------------|---------------------------|
| Videos - Read | ✅ | ✅ | ✅ |
| Videos - Write | ✅ | ❌ | ✅ |
| Videos - Delete | ✅ | ❌ | ❌ |
| Thumbnails - Read | ✅ | ✅ | ✅ |
| Thumbnails - Write | ✅ | ❌ | ✅ |
| Thumbnails - Delete | ✅ | ❌ | ❌ |

## 📞 Cloud Functions

| Function Name | Purpose | Parameters |
|--------------|---------|------------|
| `getSignedVideoURL` | Get secure video URL | `folderID`, `fileName`, `expirationHours` |
| `getSignedThumbnailURL` | Get secure thumbnail URL | `folderID`, `videoFileName`, `expirationHours` |
| `getBatchSignedVideoURLs` | Get multiple video URLs | `folderID`, `fileNames[]`, `expirationHours` |

## ⏱️ Default Expiration Times

- **Videos:** 24 hours
- **Thumbnails:** 7 days (168 hours)
- **Batch URLs:** 24 hours

## 📏 File Size Limits

- **Videos:** 500 MB max (enforced by Storage Rules)
- **Thumbnails:** 5 MB max (enforced by Storage Rules)
- **Batch Requests:** 50 files max per request

## 🔥 Firebase Console Quick Links

- **Storage:** https://console.firebase.google.com/project/YOUR_PROJECT/storage
- **Firestore:** https://console.firebase.google.com/project/YOUR_PROJECT/firestore
- **Functions:** https://console.firebase.google.com/project/YOUR_PROJECT/functions
- **Function Logs:** https://console.firebase.google.com/project/YOUR_PROJECT/functions/logs

## 🛠️ Deployment Commands

```bash
# Deploy storage rules
firebase deploy --only storage:rules

# Deploy Cloud Functions
firebase deploy --only functions

# Deploy both
firebase deploy --only storage:rules,functions

# Check function status
firebase functions:list

# View function logs
firebase functions:log
```

## 📋 Checklist for New Uploads

- [ ] Video file is < 500MB
- [ ] Folder exists in Firestore
- [ ] User has upload permission
- [ ] Thumbnail generated successfully
- [ ] Thumbnail uploaded to Storage
- [ ] Video uploaded to Storage
- [ ] Metadata saved to Firestore
- [ ] thumbnailURL field populated

## 🎓 Common Patterns

### Display video with thumbnail in list
```swift
struct VideoListItem: View {
    let video: Video
    @State private var thumbnailURL: String?
    
    var body: some View {
        HStack {
            // Thumbnail
            AsyncImage(url: thumbnailURL.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ProgressView()
            }
            .frame(width: 80, height: 60)
            
            // Title
            Text(video.fileName)
        }
        .task {
            thumbnailURL = try? await SecureURLManager.shared.getSecureThumbnailURL(
                videoFileName: video.fileName,
                folderID: video.folderID
            )
        }
    }
}
```

### Play video on tap
```swift
.onTapGesture {
    Task {
        if let url = try? await SecureURLManager.shared.getSecureVideoURL(
            fileName: video.fileName,
            folderID: video.folderID
        ) {
            showVideoPlayer(url: url)
        }
    }
}
```

---

**For detailed implementation guide, see:** `PHASE_3_DEPLOYMENT_GUIDE.md`
