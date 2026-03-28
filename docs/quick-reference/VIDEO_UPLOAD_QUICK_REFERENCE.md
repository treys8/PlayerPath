# Video Upload & Storage Quick Reference

**Last Updated:** March 27, 2026

---

## Upload Pipelines

### Athlete Upload (Auto-Queue)

```
Record/Select Video
  -> VideoCompressionService (HEVC 1080p / H.264 720p)
  -> ClipPersistenceService (save to Documents)
  -> UploadQueueManager.enqueue()
  -> VideoCloudManager.uploadVideo() -> Firebase Storage
  -> FirestoreManager.uploadVideoMetadata() -> Firestore
```

### Coach Upload (Session Clip)

```
DirectCameraRecorderView (record)
  -> PreUploadTrimmerView (optional, skip <15s)
  -> SessionAthletePickerOverlay (multi-athlete)
  -> Copy to coach_pending_uploads/
  -> UploadQueueManager.enqueueCoachUpload()
  -> CoachVideoProcessingService (thumbnail)
  -> Firebase Storage + Firestore metadata
  -> visibility: nil (coach-private until shared)
```

---

## Upload Queue

`UploadQueueManager.shared` manages all uploads with:
- Exponential backoff retries: 5s -> 15s -> 1m -> 2m -> 5m -> 10m -> 15m -> 30m -> 1hr (10 max)
- Background task support (BGTaskScheduler)
- Persistence via SwiftData `PendingUpload` model
- Connectivity awareness (ConnectivityMonitor)
- WiFi-only mode via UserPreferences

Key properties:
```swift
UploadQueueManager.shared.pendingUploads    // queued
UploadQueueManager.shared.activeUploads     // in progress
UploadQueueManager.shared.failedUploads     // exceeded retries
UploadQueueManager.shared.isProcessing      // any active work
```

---

## Video Compression

`VideoCompressionService.shared` compresses before upload:
- **Preferred:** HEVC (H.265) at 1080p
- **Fallback:** H.264 at 720p
- 30-40% typical size reduction
- Only replaces original if compressed is smaller
- Atomic swap via `replaceItemAt`

---

## Secure URL Generation

`SecureURLManager.shared` generates time-limited URLs via Cloud Functions (direct HTTPS, not HTTPSCallable):

```swift
// Single video URL (24hr default)
let url = try await SecureURLManager.shared.getSecureVideoURL(
    fileName: "video.mov", folderID: "folder123"
)

// Thumbnail URL (7-day default)
let url = try await SecureURLManager.shared.getSecureThumbnailURL(
    videoFileName: "video.mov", folderID: "folder123"
)

// Batch URLs (max 50)
let urls = try await SecureURLManager.shared.getBatchSecureVideoURLs(
    fileNames: ["v1.mov", "v2.mov"], folderID: "folder123"
)

// Clear cache
SecureURLManager.shared.clearCache()
SecureURLManager.shared.cleanExpiredURLs()
```

URLs are automatically cached for their expiration duration.

---

## Firebase Storage Paths

```
athletes/{athleteID}/videos/{clipID}/{fileName}.mov      <- personal videos
athletes/{athleteID}/photos/{photoID}/{fileName}.jpg      <- personal photos
shared_folders/{folderID}/{fileName}.mov                  <- shared videos
shared_folders/{folderID}/thumbnails/{name}_thumbnail.jpg <- thumbnails
profile_images/{userID}/profile.jpg                       <- profile pics
```

---

## Firestore Video Metadata

```json
{
    "fileName": "game_opponent_2026-03-15.mov",
    "firebaseStorageURL": "gs://...",
    "thumbnailURL": "gs://...",
    "thumbnail": {
        "standardURL": "...",
        "highQualityURL": "...",
        "timestamp": 1.0,
        "dimensions": { "width": 480, "height": 270 }
    },
    "uploadedBy": "user123",
    "uploadedByName": "Coach John",
    "uploadedByType": "coach",
    "sharedFolderID": "folder123",
    "sessionID": "session456",
    "fileSize": 52428800,
    "duration": 45.2,
    "isHighlight": false,
    "visibility": "shared",
    "viewCount": 12,
    "annotationCount": 3,
    "tags": ["batting", "mechanics"],
    "drillType": "tee_work",
    "createdAt": "2026-03-15T14:30:00Z"
}
```

---

## File Limits

| Resource | Limit |
|----------|-------|
| Video file size | 500 MB max |
| Video duration | 10 minutes max, 1 second min |
| Thumbnail file size | 5 MB max |
| Batch URL requests | 50 files max |
| Thumbnail dimensions | 480 x 270 @ 0.8 JPEG quality |

---

## Cloud Functions

| Function | Purpose | Default Expiration |
|----------|---------|-------------------|
| `getSignedVideoURL` | Single video URL | 24 hours |
| `getSignedThumbnailURL` | Single thumbnail URL | 7 days |
| `getBatchSignedVideoURLs` | Multiple video URLs | 24 hours |
| `getPersonalVideoSignedURL` | Personal (non-shared) video URL | 24 hours |

---

## Thumbnail Generation

```swift
// Generate local thumbnail from video
let result = await VideoFileManager.generateThumbnail(from: videoURL)
// Returns path to 480x270 JPEG at 0.8 quality (3x base for Retina)

// Coach video processing (generates + uploads)
let processed = await CoachVideoProcessingService.shared.processVideo(at: url, folderID: id)
// Returns ProcessedVideo(duration, thumbnailURL)
```

---

## Key Services

| Service | Role |
|---------|------|
| `VideoCloudManager` | Firebase Storage upload/download with progress |
| `UploadQueueManager` | Background queue with retries and persistence |
| `VideoCompressionService` | Pre-upload compression (HEVC/H.264) |
| `ClipPersistenceService` | Local file management |
| `VideoFileManager` | Validation and thumbnail generation |
| `SecureURLManager` | Time-limited URL generation |
| `CoachVideoProcessingService` | Post-recording coach clip processing |
| `CoachVideoCacheService` | Offline playback cache |

---

## Deployment

```bash
firebase deploy --only functions          # Cloud Functions
firebase deploy --only storage:rules      # Storage security rules
firebase functions:log                    # View function logs
```
