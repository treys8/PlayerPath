# PlayerPath Data Architecture
## Firebase + CloudKit + SwiftData Hybrid Approach

## Overview
PlayerPath uses a **hybrid backend architecture** that leverages the strengths of each service:

```
┌─────────────────────────────────────────────────────────┐
│                     PlayerPath App                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   Firebase   │  │   CloudKit   │  │  SwiftData   │ │
│  │     Auth     │  │     Sync     │  │    Local     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         │                  │                  │         │
└─────────┼──────────────────┼──────────────────┼─────────┘
          │                  │                  │
          ▼                  ▼                  ▼
   User Identity      Preferences &      Local Storage
   & Auth Tokens      App Data Sync     & Performance
```

## Service Responsibilities

### 🔐 Firebase (Authentication & Video Storage)

**Authentication:**
- ✅ User sign up / sign in / sign out
- ✅ Email/password authentication
- ✅ Password reset
- ✅ Session management
- ✅ Cross-platform auth (iOS, web, Android if needed)

**Storage (Future):**
- 📹 Video file storage
- 📹 Video streaming/CDN
- 📹 Large file handling
- 📹 Video transcoding (if using Firebase extensions)
- 📹 Thumbnail generation

**Why Firebase for these?**
- Industry-leading auth with great security
- Excellent video streaming performance
- Cost-effective for large files
- Built-in CDN for fast video delivery worldwide
- Works across Apple and non-Apple platforms

### ☁️ CloudKit (User Preferences & App Data Sync)

**Current Implementation:**
- ✅ User preferences (theme, notification settings, etc.)
- ✅ iCloud sync across user's Apple devices
- ✅ Automatic conflict resolution
- ✅ Real-time sync notifications

**Recommended for Sync:**
- ⭐️ **User Preferences** - Theme, display settings, notification prefs
- ⭐️ **Athlete Profiles** - Names, stats, metadata (NOT videos)
- ⭐️ **Game & Tournament Data** - Scores, opponents, dates
- ⭐️ **Statistics** - Batting averages, performance metrics
- ⭐️ **Video Metadata** - Filenames, tags, timestamps, Firebase URLs
- ⭐️ **Highlights** - Which videos are marked as highlights
- ⭐️ **Practice Sessions** - Session data and notes

**Why CloudKit for these?**
- Native Apple integration
- Free (within generous limits)
- Automatic sync across iPhone/iPad/Mac
- Works offline with automatic reconciliation
- Private to each user (privacy-focused)
- No server maintenance needed

### 💾 SwiftData (Local Storage & Performance)

**Current Implementation:**
- ✅ Local database for all app data
- ✅ User, Athlete, Game, Tournament, VideoClip models
- ✅ Relationships between entities
- ✅ Fast local queries

**Future Role:**
- 📱 Primary source of truth for UI
- 📱 Offline-first architecture
- 📱 Fast local queries without network
- 📱 Cache for CloudKit data

**Why SwiftData for local?**
- Ultra-fast for UI rendering
- Works completely offline
- Apple's modern persistence framework
- Type-safe with Swift
- Automatic migrations

## Data Flow Architecture

### User Authentication Flow
```
User Enters Email/Password
        ↓
Firebase Authentication
        ↓
Create/Load Local User (SwiftData)
        ↓
Trigger CloudKit Sync (preferences)
        ↓
App Ready
```

### Video Upload Flow (Future)
```
User Records Video
        ↓
Save Locally (Documents folder)
        ↓
Create VideoClip record (SwiftData)
        ↓
Upload to Firebase Storage (background)
        ↓
Get Firebase URL
        ↓
Update VideoClip with URL
        ↓
Sync VideoClip metadata to CloudKit
        ↓
Delete local video (optional, if saving space)
```

### Data Sync Flow
```
User Makes Changes
        ↓
Save to SwiftData (local)
        ↓
Sync to CloudKit (if online)
        ↓
CloudKit notifies other devices
        ↓
Other devices fetch and merge
        ↓
Update local SwiftData
        ↓
UI refreshes automatically
```

## Current Implementation Status

### ✅ Implemented
- Firebase Authentication (ComprehensiveAuthManager)
- SwiftData models (User, Athlete, Game, Tournament, VideoClip)
- Local video recording and storage
- CloudKit foundation (CloudKitManager)
- CloudKit UserPreferences sync

### 🚧 Needs Implementation

#### 1. CloudKit Schema Setup
**Create CloudKit Record Types:**
```swift
// Athlete Record
recordType: "Athlete"
fields:
  - athleteID: String (indexed)
  - userID: String (indexed, references Firebase user)
  - name: String
  - createdAt: Date
  - modifiedAt: Date

// Game Record
recordType: "Game"
fields:
  - gameID: String (indexed)
  - athleteID: Reference to Athlete
  - opponent: String
  - date: Date
  - isLive: Bool
  - score: String
  - modifiedAt: Date

// VideoMetadata Record
recordType: "VideoMetadata"
fields:
  - videoID: String (indexed)
  - athleteID: Reference to Athlete
  - gameID: Reference to Game (optional)
  - fileName: String
  - firebaseURL: String
  - thumbnailURL: String
  - duration: Double
  - playResult: String (optional)
  - isHighlight: Bool
  - createdAt: Date
  - modifiedAt: Date

// Statistics Record
recordType: "Statistics"
fields:
  - statisticsID: String (indexed)
  - athleteID: Reference to Athlete
  - hits: Int
  - atBats: Int
  - singles: Int
  - doubles: Int
  - triples: Int
  - homeRuns: Int
  - battingAverage: Double
  - sluggingPercentage: Double
  - modifiedAt: Date
```

#### 2. Expand CloudKitManager
Add methods for syncing all data types:
```swift
// Add to CloudKitManager
func syncAthlete(_ athlete: Athlete) async throws
func fetchAthletes(for userID: String) async throws -> [Athlete]
func syncGame(_ game: Game) async throws
func fetchGames(for athleteID: String) async throws -> [Game]
func syncVideoMetadata(_ video: VideoClip) async throws
func fetchVideoMetadata(for athleteID: String) async throws -> [VideoClip]
func syncStatistics(_ stats: Statistics) async throws
```

#### 3. Firebase Storage Integration
```swift
// Create FirebaseStorageManager
class FirebaseStorageManager {
    func uploadVideo(at localURL: URL, for videoID: String) async throws -> URL
    func uploadThumbnail(image: UIImage, for videoID: String) async throws -> URL
    func deleteVideo(at firebaseURL: URL) async throws
    func getVideoURL(for videoID: String) async throws -> URL
}
```

#### 4. Sync Coordinator
```swift
// Create SyncCoordinator to orchestrate all syncs
class SyncCoordinator {
    private let cloudKitManager = CloudKitManager.shared
    private let firebaseStorageManager = FirebaseStorageManager.shared
    
    func syncAll() async throws
    func syncAthlete(_ athlete: Athlete) async throws
    func syncGame(_ game: Game) async throws
    func syncVideoClip(_ video: VideoClip, uploadVideo: Bool = false) async throws
}
```

## Implementation Priority

### Phase 1: CloudKit Data Sync (Current)
1. ✅ User Preferences sync (DONE)
2. 🚧 Athlete profile sync
3. 🚧 Game data sync
4. 🚧 Statistics sync

### Phase 2: Firebase Video Storage
1. 🚧 Set up Firebase Storage in project
2. 🚧 Video upload functionality
3. 🚧 Thumbnail upload
4. 🚧 Video metadata to CloudKit
5. 🚧 Video playback from Firebase URLs

### Phase 3: Advanced Sync
1. 🚧 Conflict resolution UI
2. 🚧 Offline queue for failed syncs
3. 🚧 Background sync
4. 🚧 Selective sync (user controls)

## Security Considerations

### Firebase
- Firebase Auth tokens for authenticated requests
- Firebase Storage security rules to restrict access
- Only allow users to access their own videos

### CloudKit
- Private database - automatically secured per user
- No cross-user data access possible
- Apple handles encryption and security

### Local Storage
- SwiftData encrypted via iOS Data Protection
- Videos stored in app sandbox (protected)
- Optional: Encrypt videos before saving locally

## Cost Analysis

### Firebase (Pay-as-you-go)
**Authentication:** Free up to 50k MAU (Monthly Active Users)
**Storage:** $0.026/GB/month
**Bandwidth:** $0.12/GB downloaded

**Estimated Cost for 1000 users:**
- Storage (50GB videos): ~$1.30/month
- Bandwidth (500GB): ~$60/month
- **Total: ~$61/month**

### CloudKit (Free within limits)
**Public Database:** 1 PB storage, 200 TB transfer (FREE)
**Private Database:** 
- Storage: 1GB per user (FREE)
- Transfer: 200MB/day per user (FREE)
- Requests: 40 requests/second (FREE)

**For typical user:**
- Preferences: < 1MB
- Athlete data: < 10MB
- Video metadata: < 1MB
- **Total: Well within free tier**

### SwiftData
Free - local device storage only

## Monitoring & Debugging

### CloudKit Test View (DEBUG mode)
Location: **Profile → Settings → CloudKit Test**

Shows:
- ✅ CloudKit availability status
- ✅ iCloud sign-in status
- ✅ Sync errors
- ✅ Container registration

### Future Dashboard
- Sync status indicators
- Last sync timestamp
- Failed sync items
- Storage usage (Firebase)
- CloudKit quota usage

## Best Practices

### Syncing
1. **Always save to SwiftData first** (local source of truth)
2. **Sync to CloudKit in background** (don't block UI)
3. **Handle offline gracefully** (queue for later)
4. **Use timestamps for conflict resolution** (newest wins)
5. **Batch operations** (don't sync every keystroke)

### Video Handling
1. **Record locally first** (fast, no network needed)
2. **Upload in background** (don't block user)
3. **Keep local copy during upload** (safety)
4. **Optionally delete local after upload** (save space)
5. **Always keep thumbnail locally** (fast grid loading)

### Error Handling
1. **Retry failed syncs** (network issues are temporary)
2. **Exponential backoff** (don't spam CloudKit)
3. **User notifications for persistent failures** (tell them)
4. **Provide manual sync button** (user control)

## Testing Checklist

### CloudKit Sync
- [ ] Sign out of iCloud → Should show error gracefully
- [ ] Make change on iPhone → Should sync to iPad
- [ ] Make conflicting changes on both devices → Should resolve
- [ ] Go offline → Changes should queue
- [ ] Come back online → Queued changes should sync

### Firebase Storage (Future)
- [ ] Upload video → Should complete in background
- [ ] Kill app during upload → Should resume
- [ ] Play video from URL → Should stream smoothly
- [ ] Delete video → Should remove from Firebase

### Performance
- [ ] App should work offline completely
- [ ] UI should never wait for network
- [ ] Syncs should happen in background
- [ ] No data loss if app crashes during sync

## Next Steps

1. **Expand CloudKit schema** in iCloud Dashboard
2. **Implement Athlete sync** first (small data)
3. **Add sync status UI** (show users what's happening)
4. **Set up Firebase Storage** project
5. **Implement video upload** with progress
6. **Add conflict resolution UI** for data conflicts

## Resources

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [Firebase Storage Documentation](https://firebase.google.com/docs/storage)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- Your current implementation: `CloudKitManager.swift`, `FirebaseAuthManager.swift`
