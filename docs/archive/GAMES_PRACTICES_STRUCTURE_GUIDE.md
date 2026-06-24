# Games & Practices Folder Structure
## Complete Implementation Guide

**Date:** November 22, 2025  
**Status:** ✅ **FULLY IMPLEMENTED**

---

## 📋 Overview

Your coaches shared folders now have a **structured organization** that automatically categorizes videos into:

- **Games** 🏟️ - Videos with game context (opponent name, game date)
- **Practices** 🏃 - Videos with practice context (practice date)
- **All Videos** 📹 - Combined view of everything

---

## 🎯 How It Works

### **1. When Uploading a Video**

Users (athletes or coaches) select the context during upload:

```
Upload Screen:
┌─────────────────────────────┐
│ Video Context               │
├─────────────────────────────┤
│ ⚾ Game  │  🏃 Practice     │ ← Segmented picker
├─────────────────────────────┤
│                             │
│ [If Game Selected]          │
│ Opponent: ___________       │
│ Game Date: MM/DD/YYYY       │
│                             │
│ [If Practice Selected]      │
│ Practice Date: MM/DD/YYYY   │
│                             │
└─────────────────────────────┘
```

### **2. Video Metadata Saved to Firestore**

The metadata includes context information:

```swift
// Game video example
{
    "fileName": "game_Cardinals_11-22-2025.mov",
    "videoType": "game",
    "gameOpponent": "Cardinals",
    "gameDate": "2025-11-22T19:00:00Z",
    "uploadedBy": "coach123",
    "uploadedByName": "Coach Smith",
    "sharedFolderID": "folder456",
    "createdAt": "2025-11-22T20:15:00Z"
}

// Practice video example
{
    "fileName": "practice_11-21-2025.mov",
    "videoType": "practice",
    "practiceDate": "2025-11-21T16:00:00Z",
    "uploadedBy": "athlete789",
    "uploadedByName": "John Smith",
    "sharedFolderID": "folder456",
    "createdAt": "2025-11-21T18:30:00Z"
}
```

### **3. Viewing Folders**

When viewing a folder, users see **3 tabs**:

#### **Games Tab**
- Shows only videos with `videoType == "game"` or has `gameOpponent`
- Organized by opponent
- Collapsible sections per game
- Shows game date and number of videos

```
Games Tab:
┌──────────────────────────────┐
│ vs Cardinals                 │  ← Collapsible header
│ November 22, 2025 • 3 videos │
├──────────────────────────────┤
│ 📹 Batting - 1st Inning      │
│ 📹 Batting - 3rd Inning      │
│ 📹 Fielding - 5th Inning     │
└──────────────────────────────┘

┌──────────────────────────────┐
│ vs Blue Jays                 │
│ November 15, 2025 • 5 videos │
├──────────────────────────────┤
│ ...                          │
└──────────────────────────────┘
```

#### **Practices Tab**
- Shows only videos with `videoType == "practice"` or has `practiceDate`
- Organized by practice date
- Collapsible sections per day
- Shows date and number of videos

```
Practices Tab:
┌──────────────────────────────┐
│ Practice                     │  ← Collapsible header
│ November 21, 2025 • 4 videos │
├──────────────────────────────┤
│ 📹 Batting Drills            │
│ 📹 Pitching Form             │
│ 📹 Base Running              │
│ 📹 Team Drills               │
└──────────────────────────────┘

┌──────────────────────────────┐
│ Practice                     │
│ November 18, 2025 • 2 videos │
├──────────────────────────────┤
│ ...                          │
└──────────────────────────────┘
```

#### **All Videos Tab**
- Shows all videos regardless of type
- Sorted by upload date (newest first)
- Shows context label (Game vs X or Practice)

```
All Videos Tab:
┌──────────────────────────────┐
│ 📹 Batting - 1st Inning      │
│ 👤 Coach Smith • Nov 22      │
│ [Game vs Cardinals]          │
└──────────────────────────────┘

┌──────────────────────────────┐
│ 📹 Batting Drills            │
│ 👤 John Smith • Nov 21       │
│ [Practice]                   │
└──────────────────────────────┘
```

---

## 🏗️ Technical Implementation

### **Data Model Updates**

#### **FirestoreVideoMetadata** (Updated)
```swift
struct FirestoreVideoMetadata: Codable, Identifiable {
    var id: String?
    let fileName: String
    let firebaseStorageURL: String
    let thumbnailURL: String?
    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    let fileSize: Int64?
    let duration: Double?
    let isHighlight: Bool?
    
    // NEW: Game/Practice context
    let videoType: String? // "game" or "practice"
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?
}
```

#### **CoachVideoItem** (Updated)
```swift
struct CoachVideoItem: Identifiable {
    let id: String
    let fileName: String
    let firebaseStorageURL: String
    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    
    // NEW: Context info
    let videoType: String?
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?
    
    var contextLabel: String? {
        if let opponent = gameOpponent {
            return "Game vs \(opponent)"
        } else if let _ = practiceDate {
            return "Practice"
        }
        return nil
    }
}
```

### **Upload Flow** (CoachVideoUploadView.swift)

```swift
enum VideoContext {
    case game
    case practice
}

class CoachVideoUploadViewModel: ObservableObject {
    @Published var videoContext: VideoContext = .practice
    @Published var gameOpponent: String = ""
    @Published var contextDate: Date = Date()
    @Published var notes: String = ""
    
    private func createMetadata(...) -> [String: Any] {
        var metadata: [String: Any] = [...]
        
        // Add context-specific metadata
        switch videoContext {
        case .game:
            metadata["gameOpponent"] = gameOpponent
            metadata["gameDate"] = contextDate
            metadata["videoType"] = "game"
        case .practice:
            metadata["practiceDate"] = contextDate
            metadata["videoType"] = "practice"
        }
        
        return metadata
    }
}
```

### **Filtering Logic** (CoachFolderViewModel)

```swift
@MainActor
class CoachFolderViewModel: ObservableObject {
    @Published var videos: [CoachVideoItem] = []
    
    /// Videos marked as game videos
    var gameVideos: [CoachVideoItem] {
        videos.filter { 
            $0.videoType == "game" || $0.gameOpponent != nil 
        }
    }
    
    /// Videos marked as practice videos
    var practiceVideos: [CoachVideoItem] {
        videos.filter { 
            $0.videoType == "practice" || 
            ($0.practiceDate != nil && $0.gameOpponent == nil) 
        }
    }
}
```

### **UI Organization** (CoachFolderDetailView.swift)

```swift
// Tab picker
Picker("View", selection: $selectedTab) {
    ForEach(FolderTab.allCases, id: \.self) { tab in
        Label(tab.rawValue, systemImage: tab.icon)
            .tag(tab)
    }
}
.pickerStyle(.segmented)

// Content
Group {
    switch selectedTab {
    case .games:
        GamesTabView(folder: folder, videos: viewModel.gameVideos)
    case .practices:
        PracticesTabView(folder: folder, videos: viewModel.practiceVideos)
    case .all:
        AllVideosTabView(folder: folder, videos: viewModel.videos)
    }
}
```

---

## 📁 File Structure

### **Modified Files**

1. **`CoachVideoUploadView.swift`** ✅ Already had context picker
   - VideoContext enum (game/practice)
   - Form fields for opponent/date
   - Metadata creation with context

2. **`FirestoreManager.swift`** ✅ Updated
   - Added `videoType`, `gameOpponent`, `gameDate`, `practiceDate`, `notes` to `FirestoreVideoMetadata`

3. **`CoachFolderDetailView.swift`** ✅ Updated
   - Updated `CoachVideoItem` to include context fields
   - Updated filtering logic in `CoachFolderViewModel`
   - Already had Games/Practices/All tabs

4. **`AthleteFoldersListView.swift`** ✅ Created
   - Athlete's view uses same structure
   - Shows Games/Practices/All tabs
   - Reuses same filtering and organization

---

## 🎬 User Experience

### **Scenario 1: Coach Uploads Game Video**

1. Coach opens athlete's folder
2. Taps "+" to upload
3. Selects "Game" in context picker
4. Enters opponent: "Cardinals"
5. Selects game date: November 22, 2025
6. Adds optional notes
7. Uploads video
8. **Result:** Video appears in "Games" tab under "vs Cardinals"

### **Scenario 2: Athlete Uploads Practice Video**

1. Athlete opens their folder
2. Taps menu → "Upload Video"
3. Selects "Practice" in context picker
4. Selects practice date: November 21, 2025
5. Adds optional notes
6. Uploads video
7. **Result:** Video appears in "Practices" tab under that date

### **Scenario 3: Viewing Organized Videos**

1. User opens folder
2. Sees 3 tabs: Games | Practices | All Videos
3. Taps "Games"
4. Sees games grouped by opponent:
   - vs Cardinals (3 videos)
   - vs Blue Jays (5 videos)
   - vs Tigers (2 videos)
5. Taps "Practices"
6. Sees practices grouped by date:
   - November 21, 2025 (4 videos)
   - November 18, 2025 (2 videos)
   - November 15, 2025 (6 videos)
7. Taps "All Videos"
8. Sees chronological list with context labels

---

## 🔍 How Videos Are Categorized

### **Game Video Criteria**
A video is considered a "game video" if:
- `videoType == "game"` **OR**
- `gameOpponent != nil`

### **Practice Video Criteria**
A video is considered a "practice video" if:
- `videoType == "practice"` **OR**
- `practiceDate != nil` **AND** `gameOpponent == nil`

### **Fallback**
If a video has neither game nor practice context:
- Appears only in "All Videos" tab
- No context label shown

---

## 📊 Firestore Document Examples

### **Game Video Document**
```json
{
  "id": "video123",
  "fileName": "game_Cardinals_11-22-2025.mov",
  "firebaseStorageURL": "https://firebasestorage.googleapis.com/...",
  "uploadedBy": "coach456",
  "uploadedByName": "Coach Smith",
  "sharedFolderID": "folder789",
  "createdAt": "2025-11-22T20:15:00Z",
  "videoType": "game",
  "gameOpponent": "Cardinals",
  "gameDate": "2025-11-22T19:00:00Z",
  "notes": "Great hitting performance",
  "isHighlight": false,
  "fileSize": 125000000
}
```

### **Practice Video Document**
```json
{
  "id": "video456",
  "fileName": "practice_11-21-2025.mov",
  "firebaseStorageURL": "https://firebasestorage.googleapis.com/...",
  "uploadedBy": "athlete789",
  "uploadedByName": "John Smith",
  "sharedFolderID": "folder789",
  "createdAt": "2025-11-21T18:30:00Z",
  "videoType": "practice",
  "practiceDate": "2025-11-21T16:00:00Z",
  "notes": "Batting drills - focus on follow-through",
  "isHighlight": false,
  "fileSize": 98000000
}
```

---

## ✅ Feature Checklist

### **Upload Flow**
- [x] Context picker (Game/Practice)
- [x] Game opponent field
- [x] Game date picker
- [x] Practice date picker
- [x] Optional notes field
- [x] Metadata saved with context
- [x] Filename includes context

### **Display Flow**
- [x] Three-tab interface (Games/Practices/All)
- [x] Game videos grouped by opponent
- [x] Practice videos grouped by date
- [x] Collapsible sections
- [x] Context labels on video rows
- [x] Empty states for each tab
- [x] Proper filtering logic

### **Data Model**
- [x] `videoType` field added
- [x] `gameOpponent` field added
- [x] `gameDate` field added
- [x] `practiceDate` field added
- [x] `notes` field added
- [x] Backward compatible (optional fields)

### **Both Views**
- [x] Athlete view has same structure
- [x] Coach view has same structure
- [x] Shared filtering logic
- [x] Consistent UI/UX

---

## 🚀 Testing Guide

### **Test 1: Upload Game Video**
1. Open folder → Tap "+"
2. Select "Game" context
3. Enter opponent: "Test Team"
4. Select date
5. Upload video
6. **Verify:** 
   - Video appears in Games tab
   - Grouped under "vs Test Team"
   - Shows game date

### **Test 2: Upload Practice Video**
1. Open folder → Tap "+"
2. Select "Practice" context
3. Select date
4. Upload video
5. **Verify:**
   - Video appears in Practices tab
   - Grouped by date
   - Shows "Practice" label

### **Test 3: View All Tabs**
1. Open folder with mixed videos
2. Tap "Games" tab
3. **Verify:** Only game videos show
4. Tap "Practices" tab
5. **Verify:** Only practice videos show
6. Tap "All Videos" tab
7. **Verify:** All videos show with labels

### **Test 4: Empty States**
1. Create new folder
2. **Verify:** All tabs show empty state
3. Upload game video
4. **Verify:** 
   - Games tab shows video
   - Practices tab shows empty state
5. Upload practice video
6. **Verify:** Both tabs show videos

---

## 💡 Future Enhancements

### **Possible Improvements**

1. **Play Result Tagging**
   - Add "Single", "Double", "Triple", "Home Run", "Out"
   - Filter games by play result
   - Show stats summary per game

2. **Inning/At-Bat Number**
   - Track which inning/at-bat
   - Organize within game by inning

3. **Position Tracking**
   - Tag videos by position played
   - Filter by position

4. **Coach Annotations**
   - Add timestamp-based comments
   - Drawing overlays on video
   - Voice feedback

5. **Video Comparisons**
   - Side-by-side view
   - Compare swing mechanics over time
   - Progress tracking

6. **Statistics Integration**
   - Link videos to game stats
   - Show batting average with video clips
   - Performance trends

---

## 📝 Summary

### ✅ **Implementation Complete**

Your coaches shared folders now have:

1. **Structured Organization**
   - Games tab with opponent grouping
   - Practices tab with date grouping
   - All Videos tab with complete list

2. **Context Capture**
   - Upload form asks for context
   - Metadata saved to Firestore
   - Proper filtering and display

3. **User Experience**
   - Clean, intuitive interface
   - Collapsible sections
   - Empty states
   - Context labels

4. **Both Views Implemented**
   - Athletes see same structure
   - Coaches see same structure
   - Consistent experience

### 🎯 **How It Works**

1. User uploads video → Selects Game or Practice
2. Metadata saved with context → videoType, opponent, date
3. Videos filtered by context → Games vs Practices
4. Displayed in organized tabs → Grouped appropriately

**The structure is production-ready!** 🚀

---

## 📞 Need Help?

If you need to modify the structure:

1. **Change grouping logic:** Edit `gameGroups` or `practiceGroups` computed properties
2. **Add new context types:** Extend `VideoContext` enum
3. **Change UI layout:** Modify `GamesTabView` or `PracticesTabView`
4. **Add metadata fields:** Update `FirestoreVideoMetadata` struct

All the pieces are modular and easy to customize!
