# PlayerPath Production Roadmap
**Last Updated:** January 25, 2026

---

## 📊 Current Status

### ✅ Completed (Phases 1-2)
- ✅ User authentication & profiles (Firebase Auth + Firestore)
- ✅ Athletes cross-device sync (Phase 1)
- ✅ Seasons cross-device sync (Phase 2)
- ✅ Games cross-device sync (Phase 2)
- ✅ Video recording (2 modes: Quick Record + Advanced)
- ✅ Video library with full-screen player
- ✅ Play result tagging (1B, 2B, 3B, HR, etc.)
- ✅ Statistics tracking (AVG, SLG, OPS)
- ✅ Dashboard with quick actions
- ✅ Offline-first architecture

### 🔄 In Progress
- Phase 3: Practices + Video metadata sync
- Phase 4: Statistics sync
- Production readiness tasks

---

## 🎯 Phase 3: Practices & Video Metadata Sync

### **Goal**
Enable cross-device access to practice sessions and video metadata (without syncing actual video files).

### **Scope**
- Sync practice sessions to Firestore
- Sync practice notes to Firestore
- Sync video clip metadata to Firestore
- Sync play results to Firestore
- Link videos to athletes/games/practices across devices

### **Implementation Plan**

#### **Step 1: Add Sync Fields to Models** (1 hour)
**Files to modify:**
- `Models.swift`

**Changes:**
```swift
// Practice model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var isDeletedRemotely: Bool = false
var version: Int = 0

// PracticeNote model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var version: Int = 0

// VideoClip model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var isDeletedRemotely: Bool = false
var version: Int = 0

// PlayResult model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var version: Int = 0
```

#### **Step 2: Add Firestore Schema & Models** (2 hours)
**Files to modify:**
- `FirestoreManager.swift`

**New Firestore Collections:**

**`/users/{userId}/practices/{practiceId}`**
```typescript
{
  id: string,
  athleteId: string,
  seasonId: string | null,
  date: timestamp,
  createdAt: timestamp,
  updatedAt: timestamp,
  version: number,
  isDeleted: boolean
}
```

**`/users/{userId}/practice-notes/{noteId}`**
```typescript
{
  id: string,
  practiceId: string,
  content: string,
  createdAt: timestamp
}
```

**`/users/{userId}/video-clips/{clipId}`**
```typescript
{
  id: string,
  athleteId: string,
  gameId: string | null,
  practiceId: string | null,
  seasonId: string | null,
  fileName: string,
  // NOTE: filePath is LOCAL only - not synced
  // Videos stay on device unless uploaded to Firebase Storage
  thumbnailPath: string,  // Local path
  createdAt: timestamp,
  updatedAt: timestamp,
  isHighlight: boolean,
  version: number,
  isDeleted: boolean
}
```

**`/users/{userId}/play-results/{resultId}`**
```typescript
{
  id: string,
  videoClipId: string,
  type: "single" | "double" | "triple" | "homeRun" | "walk" | "strikeout" | "groundOut" | "flyOut",
  createdAt: timestamp
}
```

**New Swift Models:**
```swift
struct FirestorePractice: Codable, Identifiable
struct FirestorePracticeNote: Codable, Identifiable
struct FirestoreVideoClip: Codable, Identifiable
struct FirestorePlayResult: Codable, Identifiable
```

#### **Step 3: Add Firestore CRUD Methods** (3 hours)
**File:** `FirestoreManager.swift`

**Methods to add:**
```swift
// Practices
func createPractice(userId: String, data: [String: Any]) async throws -> String
func updatePractice(userId: String, practiceId: String, data: [String: Any]) async throws
func fetchPractices(userId: String) async throws -> [FirestorePractice]
func deletePractice(userId: String, practiceId: String) async throws

// Practice Notes
func createPracticeNote(userId: String, data: [String: Any]) async throws -> String
func updatePracticeNote(userId: String, noteId: String, data: [String: Any]) async throws
func fetchPracticeNotes(userId: String, practiceId: String) async throws -> [FirestorePracticeNote]
func deletePracticeNote(userId: String, noteId: String) async throws

// Video Clips
func createVideoClip(userId: String, data: [String: Any]) async throws -> String
func updateVideoClip(userId: String, clipId: String, data: [String: Any]) async throws
func fetchVideoClips(userId: String) async throws -> [FirestoreVideoClip]
func deleteVideoClip(userId: String, clipId: String) async throws

// Play Results
func createPlayResult(userId: String, data: [String: Any]) async throws -> String
func updatePlayResult(userId: String, resultId: String, data: [String: Any]) async throws
func fetchPlayResults(userId: String, videoClipId: String) async throws -> [FirestorePlayResult]
func deletePlayResult(userId: String, resultId: String) async throws
```

#### **Step 4: Extend SyncCoordinator** (4 hours)
**File:** `SyncCoordinator.swift`

**New methods:**
```swift
func syncPractices(for user: User) async throws
func syncVideoClips(for user: User) async throws
func syncPlayResults(for user: User) async throws

private func uploadLocalPractices(_ user: User, context: ModelContext) async throws
private func downloadRemotePractices(_ user: User, context: ModelContext) async throws
private func uploadLocalVideoClips(_ user: User, context: ModelContext) async throws
private func downloadRemoteVideoClips(_ user: User, context: ModelContext) async throws
private func uploadLocalPlayResults(_ user: User, context: ModelContext) async throws
private func downloadRemotePlayResults(_ user: User, context: ModelContext) async throws
```

**Update `syncAll()` to include new entities:**
```swift
func syncAll(for user: User) async throws {
    print("🔄 Starting comprehensive sync (Athletes → Seasons → Games → Practices → Videos)")

    try await syncAthletes(for: user)
    try await syncSeasons(for: user)
    try await syncGames(for: user)
    try await syncPractices(for: user)      // NEW
    try await syncVideoClips(for: user)      // NEW
    try await syncPlayResults(for: user)     // NEW

    lastSyncDate = Date()
}
```

#### **Step 5: Update Firestore Security Rules** (30 min)
**File:** `firestore.rules`

```javascript
// Practices
match /practices/{practiceId} {
  allow read: if isAuthenticated() && isOwner(userID);
  allow create, update: if isAuthenticated() && isOwner(userID);
  allow delete: if isAuthenticated() && isOwner(userID);
}

// Practice Notes
match /practice-notes/{noteId} {
  allow read: if isAuthenticated() && isOwner(userID);
  allow create, update: if isAuthenticated() && isOwner(userID);
  allow delete: if isAuthenticated() && isOwner(userID);
}

// Video Clips
match /video-clips/{clipId} {
  allow read: if isAuthenticated() && isOwner(userID);
  allow create, update: if isAuthenticated() && isOwner(userID);
  allow delete: if isAuthenticated() && isOwner(userID);
}

// Play Results
match /play-results/{resultId} {
  allow read: if isAuthenticated() && isOwner(userID);
  allow create, update: if isAuthenticated() && isOwner(userID);
  allow delete: if isAuthenticated() && isOwner(userID);
}
```

#### **Step 6: Update UI to Mark for Sync** (2 hours)
**Files to modify:**
- `PracticesView.swift` - Mark practices as needsSync when created/edited
- `DirectCameraRecorderView.swift` - Mark video clips as needsSync when saved
- `VideoRecorderView_Refactored.swift` - Mark video clips as needsSync when saved

**Example:**
```swift
// In DirectCameraRecorderView.swift after saving video
clip.needsSync = true
modelContext.insert(clip)
try modelContext.save()

Task {
    guard let user = athlete?.user else { return }
    try await SyncCoordinator.shared.syncVideoClips(for: user)
}
```

#### **Step 7: Testing** (2 hours)
- Create practice on Device A → syncs to Device B
- Record video on Device A → metadata appears on Device B
- Tag play result on Device A → syncs to Device B
- Delete practice on Device A → soft deletes on Device B
- Verify video files stay local (only metadata syncs)

---

## 📈 Phase 4: Statistics Sync

### **Goal**
Sync statistics across devices with server-side calculation for consistency.

### **Scope**
- Sync athlete statistics to Firestore
- Sync game statistics to Firestore
- Implement server-side statistics calculation (Cloud Function)
- Real-time statistics updates across devices

### **Implementation Plan**

#### **Step 1: Add Sync Fields to Statistics Models** (30 min)
**File:** `Models.swift`

```swift
// AthleteStatistics model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var version: Int = 0

// GameStatistics model
var firestoreId: String?
var lastSyncDate: Date?
var needsSync: Bool = false
var version: Int = 0
```

#### **Step 2: Firestore Schema** (1 hour)
**File:** `FirestoreManager.swift`

**`/users/{userId}/statistics/{statsId}`**
```typescript
{
  id: string,
  athleteId: string,
  seasonId: string | null,  // null = overall stats

  // Raw counts
  totalGames: number,
  atBats: number,
  hits: number,
  singles: number,
  doubles: number,
  triples: number,
  homeRuns: number,
  runs: number,
  rbis: number,
  walks: number,
  strikeouts: number,
  groundOuts: number,
  flyOuts: number,

  // Computed (calculated server-side)
  battingAverage: number,
  onBasePercentage: number,
  sluggingPercentage: number,
  ops: number,

  updatedAt: timestamp,
  version: number
}
```

**`/users/{userId}/game-statistics/{gameStatsId}`**
```typescript
{
  id: string,
  gameId: string,
  athleteId: string,

  atBats: number,
  hits: number,
  singles: number,
  doubles: number,
  triples: number,
  homeRuns: number,
  runs: number,
  rbis: number,
  walks: number,
  strikeouts: number,
  groundOuts: number,
  flyOuts: number,

  updatedAt: timestamp
}
```

#### **Step 3: Server-Side Statistics Calculation** (3 hours)
**New file:** `functions/src/statistics.ts` (Cloud Functions)

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Trigger when play result is created/updated/deleted
export const recalculateAthleteStats = functions.firestore
  .document('users/{userId}/play-results/{resultId}')
  .onWrite(async (change, context) => {
    const { userId } = context.params;

    // Get athleteId from video clip
    const resultData = change.after.exists ? change.after.data() : change.before.data();
    const videoClipId = resultData?.videoClipId;

    const videoClipDoc = await admin.firestore()
      .collection('users').doc(userId)
      .collection('video-clips').doc(videoClipId)
      .get();

    const athleteId = videoClipDoc.data()?.athleteId;
    if (!athleteId) return;

    // Aggregate all play results for this athlete
    const playResultsSnapshot = await admin.firestore()
      .collection('users').doc(userId)
      .collection('play-results')
      .get();

    const stats = {
      totalGames: 0,
      atBats: 0,
      hits: 0,
      singles: 0,
      doubles: 0,
      triples: 0,
      homeRuns: 0,
      runs: 0,
      rbis: 0,
      walks: 0,
      strikeouts: 0,
      groundOuts: 0,
      flyOuts: 0
    };

    // Aggregate counts from play results
    for (const doc of playResultsSnapshot.docs) {
      const result = doc.data();
      const clipDoc = await admin.firestore()
        .collection('users').doc(userId)
        .collection('video-clips').doc(result.videoClipId)
        .get();

      if (clipDoc.data()?.athleteId === athleteId) {
        switch (result.type) {
          case 'single':
            stats.singles++;
            stats.hits++;
            stats.atBats++;
            break;
          case 'double':
            stats.doubles++;
            stats.hits++;
            stats.atBats++;
            break;
          case 'triple':
            stats.triples++;
            stats.hits++;
            stats.atBats++;
            break;
          case 'homeRun':
            stats.homeRuns++;
            stats.hits++;
            stats.atBats++;
            break;
          case 'walk':
            stats.walks++;
            break;
          case 'strikeout':
            stats.strikeouts++;
            stats.atBats++;
            break;
          case 'groundOut':
            stats.groundOuts++;
            stats.atBats++;
            break;
          case 'flyOut':
            stats.flyOuts++;
            stats.atBats++;
            break;
        }
      }
    }

    // Calculate percentages
    const battingAverage = stats.atBats > 0 ? stats.hits / stats.atBats : 0;
    const onBasePercentage = (stats.atBats + stats.walks) > 0
      ? (stats.hits + stats.walks) / (stats.atBats + stats.walks)
      : 0;
    const sluggingPercentage = stats.atBats > 0
      ? (stats.singles + (stats.doubles * 2) + (stats.triples * 3) + (stats.homeRuns * 4)) / stats.atBats
      : 0;
    const ops = onBasePercentage + sluggingPercentage;

    // Update statistics document
    await admin.firestore()
      .collection('users').doc(userId)
      .collection('statistics').doc(athleteId)
      .set({
        ...stats,
        athleteId,
        seasonId: null,  // Overall stats
        battingAverage,
        onBasePercentage,
        sluggingPercentage,
        ops,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        version: admin.firestore.FieldValue.increment(1)
      }, { merge: true });

    console.log(`✅ Recalculated statistics for athlete ${athleteId}`);
  });
```

#### **Step 4: Deploy Cloud Function** (1 hour)
```bash
cd functions
npm install
firebase deploy --only functions
```

#### **Step 5: Extend SyncCoordinator for Statistics** (2 hours)
**File:** `SyncCoordinator.swift`

```swift
func syncStatistics(for user: User) async throws {
    // Statistics are READ-ONLY from client
    // All writes happen server-side via Cloud Functions
    // Just download latest stats from Firestore

    let remoteStats = try await FirestoreManager.shared.fetchStatistics(userId: user.id.uuidString)

    for remoteStat in remoteStats {
        // Find local athlete
        let athlete = (user.athletes ?? []).first {
            $0.id.uuidString == remoteStat.athleteId || $0.firestoreId == remoteStat.athleteId
        }

        guard let athlete = athlete else { continue }

        // Update local statistics
        if athlete.statistics == nil {
            let stats = AthleteStatistics()
            athlete.statistics = stats
            modelContext?.insert(stats)
        }

        athlete.statistics?.atBats = remoteStat.atBats
        athlete.statistics?.hits = remoteStat.hits
        athlete.statistics?.singles = remoteStat.singles
        athlete.statistics?.doubles = remoteStat.doubles
        athlete.statistics?.triples = remoteStat.triples
        athlete.statistics?.homeRuns = remoteStat.homeRuns
        athlete.statistics?.runs = remoteStat.runs
        athlete.statistics?.rbis = remoteStat.rbis
        athlete.statistics?.walks = remoteStat.walks
        athlete.statistics?.strikeouts = remoteStat.strikeouts
        athlete.statistics?.totalGames = remoteStat.totalGames
        athlete.statistics?.updatedAt = Date()
    }

    try modelContext?.save()
}
```

#### **Step 6: Update Firestore Security Rules** (15 min)
```javascript
match /statistics/{statsId} {
  // Read: Users can read their own stats
  allow read: if isAuthenticated() && isOwner(userID);

  // Write: ONLY Cloud Functions can write
  // Prevents client-side tampering with statistics
  allow write: if false;
}

match /game-statistics/{gameStatsId} {
  allow read: if isAuthenticated() && isOwner(userID);
  allow write: if false;  // Server-side only
}
```

#### **Step 7: Testing** (2 hours)
- Tag play result on Device A
- Wait for Cloud Function to process (1-2 seconds)
- Verify statistics update on Device A
- Refresh on Device B → should see updated statistics
- Verify statistics are calculated correctly
- Test edge cases (no at-bats, all walks, etc.)

---

## 🚀 Production Readiness Plan

### **Critical Tasks (Must Complete Before Launch)**

#### **1. Privacy Policy** (4 hours)
**Priority:** 🔴 CRITICAL

**Steps:**
1. Use [iubenda.com](https://www.iubenda.com) or [termly.io](https://termly.io) template generator
2. Customize for PlayerPath:
   - Data collected: Email, name, video files, statistics
   - Third parties: Firebase (Auth, Firestore, Storage), Apple Sign In
   - Data retention: Account deletion removes all data
   - User rights: Access, delete, export data
3. Create `PrivacyPolicyView.swift`
4. Add link in More tab + signup flow

**Implementation:**
```swift
// PrivacyPolicyView.swift
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Last updated: January 25, 2026")
                    .foregroundColor(.secondary)

                // Privacy policy content
                Text(privacyPolicyText)
                    .font(.body)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
    }

    private let privacyPolicyText = """
    [Generated from template service]
    """
}
```

#### **2. Terms of Service** (4 hours)
**Priority:** 🔴 CRITICAL

**Steps:**
1. Use legal template generator
2. Customize for PlayerPath:
   - User responsibilities: Appropriate content, own video rights
   - Service availability: No uptime guarantees, beta software
   - Liability limitations: Not responsible for lost data
   - Termination: Can suspend accounts for violations
3. Create `TermsOfServiceView.swift`
4. Add link in More tab + signup flow
5. Require acceptance during signup

**Implementation:**
```swift
// Add to signup flow
@State private var acceptedTerms = false

VStack {
    Toggle(isOn: $acceptedTerms) {
        HStack {
            Text("I agree to the")
            Button("Terms of Service") {
                showingTerms = true
            }
            Text("and")
            Button("Privacy Policy") {
                showingPrivacy = true
            }
        }
        .font(.caption)
    }

    Button("Sign Up") {
        // ...
    }
    .disabled(!acceptedTerms)
}
```

#### **3. Help & Support** (6 hours)
**Priority:** 🔴 CRITICAL

**Create comprehensive help system:**

**Files to create:**
- `HelpView.swift` - Main help screen
- `FAQView.swift` - Frequently Asked Questions
- `ContactSupportView.swift` - Email/feedback form

**Implementation:**
```swift
struct HelpView: View {
    var body: some View {
        List {
            Section("Getting Started") {
                NavigationLink("Creating Your First Athlete") {
                    HelpArticleView(article: .createAthlete)
                }
                NavigationLink("Recording a Video") {
                    HelpArticleView(article: .recordVideo)
                }
                NavigationLink("Tagging Play Results") {
                    HelpArticleView(article: .tagPlays)
                }
            }

            Section("Managing Data") {
                NavigationLink("Creating Seasons") {
                    HelpArticleView(article: .seasons)
                }
                NavigationLink("Tracking Games") {
                    HelpArticleView(article: .games)
                }
                NavigationLink("Understanding Statistics") {
                    HelpArticleView(article: .statistics)
                }
            }

            Section("Account & Privacy") {
                NavigationLink("Exporting Your Data") {
                    HelpArticleView(article: .export)
                }
                NavigationLink("Deleting Your Account") {
                    HelpArticleView(article: .deleteAccount)
                }
            }

            Section("Support") {
                NavigationLink("Frequently Asked Questions") {
                    FAQView()
                }
                NavigationLink("Contact Support") {
                    ContactSupportView()
                }
            }
        }
        .navigationTitle("Help & Support")
    }
}
```

**FAQ Topics:**
- How do I record a video?
- What do the statistics mean?
- How do I switch between athletes?
- Can I share videos with coaches?
- How do I delete a game?
- What happens to my data if I delete my account?
- Why aren't my videos syncing across devices? (explain: videos are local, metadata syncs)

#### **4. Data Export** (4 hours)
**Priority:** 🔴 CRITICAL (GDPR compliance)

**Create data export feature:**

**File:** `DataExportView.swift`

```swift
struct DataExportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Export Your Data")
                .font(.title)
                .fontWeight(.bold)

            Text("Download all your athletes, games, videos, and statistics as a JSON file.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button {
                exportData()
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Text("Export Data")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
        .padding()
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL = exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    private func exportData() {
        isExporting = true

        Task {
            do {
                // Fetch all user data
                guard let user = authManager.localUser else { return }

                let exportData: [String: Any] = [
                    "exportDate": ISO8601DateFormatter().string(from: Date()),
                    "user": [
                        "email": user.email,
                        "username": user.username
                    ],
                    "athletes": (user.athletes ?? []).map { $0.toExportData() },
                    "statistics": user.athletes?.compactMap { $0.statistics?.toExportData() } ?? []
                ]

                // Convert to JSON
                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)

                // Save to file
                let fileName = "PlayerPath_Export_\(ISO8601DateFormatter().string(from: Date())).json"
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try jsonData.write(to: fileURL)

                await MainActor.run {
                    exportURL = fileURL
                    showingShareSheet = true
                    isExporting = false
                }
            } catch {
                print("Export failed: \(error)")
                isExporting = false
            }
        }
    }
}

// Helper extension
extension Athlete {
    func toExportData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "name": name,
            "createdAt": createdAt?.ISO8601Format() ?? "",
            "seasons": (seasons ?? []).map { season in
                [
                    "name": season.name,
                    "startDate": season.startDate?.ISO8601Format() ?? "",
                    "endDate": season.endDate?.ISO8601Format() ?? "",
                    "isActive": season.isActive
                ]
            },
            "games": (seasons?.flatMap { $0.games ?? [] } ?? []).map { game in
                [
                    "opponent": game.opponent,
                    "date": game.date?.ISO8601Format() ?? "",
                    "isComplete": game.isComplete
                ]
            }
        ]
    }
}
```

#### **5. Account Deletion UI** (2 hours)
**Priority:** 🔴 CRITICAL

**Add delete button to ProfileView/More tab:**

```swift
// In ProfileView.swift
Section("Danger Zone") {
    Button(role: .destructive) {
        showingDeleteAccountConfirmation = true
    } label: {
        Label("Delete Account", systemImage: "trash")
            .foregroundColor(.red)
    }
}
.alert("Delete Account", isPresented: $showingDeleteAccountConfirmation) {
    Button("Cancel", role: .cancel) { }
    Button("Delete", role: .destructive) {
        deleteAccount()
    }
} message: {
    Text("This will permanently delete your account and all associated data. This action cannot be undone.")
}

private func deleteAccount() {
    Task {
        do {
            try await authManager.deleteAccount()
            // User will be signed out automatically
        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            showingError = true
        }
    }
}
```

#### **6. App Store Assets** (8 hours)
**Priority:** 🔴 CRITICAL

**Required assets:**

**Screenshots (5 required per device):**
- iPhone 6.7" (iPhone 17 Pro Max): 1290 x 2796
- iPhone 6.5": 1284 x 2778
- iPad Pro (6th Gen) 12.9": 2048 x 2732

**Screenshots to capture:**
1. Dashboard with live game
2. Video recording interface
3. Video library with tagged plays
4. Statistics view
5. Game detail with play-by-play

**App Preview Video (Optional but recommended):**
- 30 second video showing key features
- Portrait orientation
- Include: Record → Tag → View Stats flow

**App Icon:**
- 1024x1024 PNG (already have)
- Ensure no alpha channel

**App Store Description:**
```
PlayerPath - Baseball & Softball Video Tracker

Track every at-bat with instant video recording and comprehensive statistics.

FEATURES:
• Quick Record - Capture moments in seconds
• Smart Tagging - Tag hits, outs, and more
• Live Stats - Real-time batting average, slugging, OPS
• Cross-Device Sync - Access your data anywhere
• Season Tracking - Organize by baseball/softball seasons
• Game Management - Track live games with play-by-play
• Highlights - Automatically save your best moments

Perfect for players, parents, and coaches who want to analyze performance and track progress over time.

No subscription required for core features.
```

**Keywords:**
baseball, softball, video, statistics, tracker, hitting, batting, stats, recorder, youth sports

#### **7. TestFlight Beta Testing** (1 week)
**Priority:** 🟡 IMPORTANT

**Steps:**
1. Upload build to App Store Connect
2. Create internal testing group (you + trusted testers)
3. Distribute to 10-20 external beta testers
4. Collect feedback via TestFlight feedback + Google Form
5. Fix critical bugs
6. Repeat until stable

**Feedback to collect:**
- Crashes or bugs
- Confusing UI/UX
- Missing features
- Performance issues
- Suggestions for improvement

---

### **Important Tasks (Should Complete Before Launch)**

#### **8. Crash Reporting** (2 hours)
**Priority:** 🟡 IMPORTANT

**Setup Firebase Crashlytics:**

```swift
// 1. Add to Podfile/Package.swift
dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0")
]

// 2. In PlayerPathApp.swift
import FirebaseCrashlytics

init() {
    FirebaseApp.configure()
    Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
}

// 3. Test with forced crash (remove before production)
Button("Test Crash") {
    fatalError("Test crash for Crashlytics")
}
```

**Benefits:**
- Automatic crash reporting
- Stack traces with line numbers
- User impact metrics
- Crash-free user percentage

#### **9. Analytics Instrumentation** (4 hours)
**Priority:** 🟡 IMPORTANT

**Track key events:**

```swift
import FirebaseAnalytics

// Video Recording
Analytics.logEvent("video_recorded", parameters: [
    "recording_mode": "quick_record",
    "video_duration": 45
])

// Play Result Tagged
Analytics.logEvent("play_result_tagged", parameters: [
    "result_type": "homeRun"
])

// Game Created
Analytics.logEvent("game_created", parameters: [
    "is_live": true
])

// Statistics Viewed
Analytics.logEvent("statistics_viewed", parameters: nil)
```

**Metrics to track:**
- Daily/Monthly Active Users
- Video recording frequency
- Most common play results
- Crash-free user rate
- Session duration
- Feature adoption (seasons, games, highlights)

#### **10. Onboarding Tutorial** (6 hours)
**Priority:** 🟡 IMPORTANT

**Create 4-screen onboarding:**

```swift
struct OnboardingView: View {
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            OnboardingPage(
                icon: "person.fill",
                title: "Create Your Athlete",
                description: "Set up profiles for yourself or your players",
                pageNumber: 0
            )

            OnboardingPage(
                icon: "video.fill",
                title: "Record Every At-Bat",
                description: "Quick Record captures moments in seconds",
                pageNumber: 1
            )

            OnboardingPage(
                icon: "tag.fill",
                title: "Tag Your Results",
                description: "Mark hits, outs, and more for instant statistics",
                pageNumber: 2
            )

            OnboardingPage(
                icon: "chart.bar.fill",
                title: "Track Progress",
                description: "View batting average, slugging, and detailed stats",
                pageNumber: 3
            )
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
```

**Show onboarding:**
- First app launch
- After signup
- Can be skipped
- Can be re-accessed from Help

---

### **Nice to Have (Post-Launch)**

#### **11. Push Notifications** (4 hours)
- Game reminders
- Weekly stats summary
- Video backup reminders

#### **12. Video Sharing** (6 hours)
- Export video to camera roll
- Share to Instagram/Twitter
- Generate highlight reel

#### **13. Statistics Export** (4 hours)
- Export as PDF report
- Export as CSV spreadsheet
- Email stats to coaches

#### **14. Dark Mode Optimization** (4 hours)
- Test all screens in dark mode
- Adjust colors for better contrast
- Fix any visual bugs

#### **15. Accessibility Audit** (6 hours)
- VoiceOver testing
- Dynamic Type support
- Color contrast validation
- Keyboard navigation

#### **16. iPad Optimization** (8 hours)
- Multi-column layouts
- Drag and drop support
- Keyboard shortcuts
- Larger canvas usage

---

## 📅 Timeline Estimates

### **Fast Track to Production (3 weeks)**

**Week 1: Sync Completion**
- Mon-Tue: Phase 3 implementation (Practices + Videos)
- Wed-Thu: Phase 4 implementation (Statistics + Cloud Function)
- Fri: Testing and bug fixes

**Week 2: Production Readiness**
- Mon: Privacy Policy + Terms of Service
- Tue: Help & Support system
- Wed: Data Export + Account Deletion UI
- Thu: App Store assets (screenshots, description)
- Fri: TestFlight build + internal testing

**Week 3: Beta Testing & Polish**
- Mon-Wed: External beta testing
- Thu: Bug fixes from feedback
- Fri: Final build + App Store submission

### **Recommended Timeline (4-5 weeks)**

**Week 1: Phase 3**
- Implementation, testing, bug fixes

**Week 2: Phase 4**
- Implementation, Cloud Function deployment, testing

**Week 3: Legal & Help**
- Privacy Policy, Terms, Help system, data export

**Week 4: App Store Prep**
- Screenshots, description, TestFlight setup
- Internal testing

**Week 5: Beta & Launch**
- External beta testing
- Bug fixes
- App Store submission

---

## ✅ Launch Checklist

### **Pre-Launch**
- [ ] Phase 3 complete (Practices + Videos sync)
- [ ] Phase 4 complete (Statistics sync)
- [ ] Privacy Policy added and linked
- [ ] Terms of Service added and linked
- [ ] Help & Support system implemented
- [ ] Data Export functional
- [ ] Account Deletion UI added
- [ ] App Store screenshots (5 per device)
- [ ] App Store description written
- [ ] App Store keywords selected
- [ ] TestFlight build uploaded
- [ ] Internal testing complete (no crashes)
- [ ] External beta testing complete (10+ testers)
- [ ] Critical bugs fixed
- [ ] Crash reporting enabled
- [ ] Analytics instrumented
- [ ] Onboarding tutorial added

### **App Store Submission**
- [ ] App icon uploaded (1024x1024)
- [ ] Screenshots uploaded (all device sizes)
- [ ] App preview video uploaded (optional)
- [ ] Privacy policy URL provided
- [ ] App description finalized
- [ ] Keywords optimized
- [ ] Age rating completed
- [ ] Pricing & availability set
- [ ] App Review information provided
- [ ] Build submitted for review

### **Post-Launch**
- [ ] Monitor crash reports
- [ ] Respond to user reviews
- [ ] Track analytics metrics
- [ ] Plan feature updates
- [ ] Fix bugs as reported

---

## 🎯 Priority Recommendation

**If you want to launch ASAP:**

1. **Skip Phase 3 & 4 for v1.0** - Athletes, Seasons, and Games sync is enough for cross-device
2. **Focus on production readiness:**
   - Privacy Policy & Terms (1 day)
   - Help & Support (1 day)
   - Data Export + Account Deletion (1 day)
   - App Store assets (2 days)
   - TestFlight beta (3-5 days)
3. **Launch v1.0 in 1-2 weeks**
4. **Release v1.1 with Phase 3 & 4** (1-2 weeks post-launch)

**This gets the app to users faster while maintaining compliance and core functionality.**

What do you want to tackle first?
