# Season Management UI Flow Guide

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      ATHLETE PROFILE                         │
│                                                              │
│  👤 John Smith                                               │
│  ⚾ Spring 2025  ▼  ◄── SeasonIndicatorView (tap to change) │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ 📢 Season Check                                     │    │
│  │ Spring 2025 has been active for 6+ months.        │    │
│  │ Consider ending it and starting a new season      │    │
│  │                                    [Manage] [X]    │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  📊 Dashboard Content...                                    │
│  🎮 Games, Videos, Stats                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Tap "⚾ Spring 2025 ▼"
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    SEASON MANAGEMENT                         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Active Season                                       │    │
│  ├────────────────────────────────────────────────────┤    │
│  │  ⚾ Spring 2025                                     │    │
│  │  Started Mar 1, 2025                               │    │
│  │                                                     │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │    │
│  │  │ 🎮 15    │  │ 🎥 45    │  │ ⭐ 12    │        │    │
│  │  │ Games    │  │ Videos   │  │Highlights│        │    │
│  │  └──────────┘  └──────────┘  └──────────┘        │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Actions                                             │    │
│  ├────────────────────────────────────────────────────┤    │
│  │ 📦 End Current Season                              │    │
│  │ ➕ Start New Season                                │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Season History                                      │    │
│  ├────────────────────────────────────────────────────┤    │
│  │ ⚾ Fall 2024                           ✓           │    │
│  │ Oct 1, 2024 - Dec 15, 2024                         │    │
│  │ 12 games • 38 videos                               │    │
│  │                                                     │    │
│  │ ⚾ Spring 2024                         ✓           │    │
│  │ Mar 1, 2024 - Jun 10, 2024                         │    │
│  │ 18 games • 52 videos                               │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│                                             [+] (toolbar)    │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Tap "Start New Season"
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     CREATE SEASON                            │
│                                                              │
│  Season Information                                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Season Name: [Fall 2025                      ]     │    │
│  │                                                     │    │
│  │ Suggestions:                                       │    │
│  │ [Fall 2025] [Fall Season] [2025 Season]           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  When does this season start?                               │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Start Date:  Sep 1, 2025  📅                       │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  Sport                                                       │
│  ┌────────────────────────────────────────────────────┐    │
│  │  [  Baseball  ] [  Softball  ]                     │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ ✓ Make this the active season                      │    │
│  │                                                     │    │
│  │ If enabled, this will end the current active      │    │
│  │ season and make this one active.                   │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  [Cancel]                              [Create]             │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Tap "Create"
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 SEASON CREATED! ✅                           │
│                                                              │
│  • Previous season "Spring 2025" archived                   │
│  • New season "Fall 2025" is now active                     │
│  • All new games/videos will be added to Fall 2025          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  GAMES VIEW (Updated)                        │
│                                                              │
│  ⚾ Fall 2025  ▼  ◄── Shows active season                   │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ ⚙️ Show All Seasons                           ○    │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  Upcoming                                                    │
│  • vs Panthers - Sep 5, 2025                                │
│  • vs Tigers - Sep 8, 2025                                  │
│                                                              │
│  Past (Fall 2025 only)                                      │
│  • vs Wildcats - Aug 28, 2025 (W 5-3)                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## User Journeys

### Journey 1: New User (First Time)

```
1. User creates athlete "Sarah"
   ↓
2. App detects no seasons exist
   ↓
3. Shows CreateFirstSeasonPrompt
   ┌────────────────────────────────────┐
   │  🗓️ Start Your First Season        │
   │                                     │
   │  Organize your baseball journey by  │
   │  season. All games, practices, and  │
   │  videos will be saved in your       │
   │  active season.                     │
   │                                     │
   │  [Create Season]                    │
   │  I'll Do This Later                 │
   └────────────────────────────────────┘
   ↓
4a. If "Create Season" → CreateSeasonView
4b. If "Later" → Auto-create "Spring 2025" silently
   ↓
5. User records first game → auto-linked to season
```

### Journey 2: Existing User (Migration)

```
1. User with 50 games, 0 seasons opens app
   ↓
2. Migration system detects unlinked data
   ↓
3. Auto-groups games by date:
   - Spring 2024: 18 games (Mar-Jun)
   - Fall 2024: 20 games (Sep-Dec)  
   - Spring 2025: 12 games (Mar-present)
   ↓
4. Creates 3 seasons automatically
   ↓
5. Links all games to appropriate seasons
   ↓
6. Makes "Spring 2025" active
   ↓
7. User sees organized history! ✅
```

### Journey 3: End of Season

```
1. User finishes spring season (June)
   ↓
2. App shows recommendation:
   "Spring 2025 has been active for 4 months"
   ↓
3. User taps "Manage" → Season Management
   ↓
4. Taps "End Current Season"
   ↓
5. Confirmation alert:
   "Are you sure you want to end Spring 2025?
    This will archive all games, practices, and
    videos for this season."
   ↓
6. User confirms
   ↓
7. Season archived:
   - End date set to today
   - Statistics calculated and saved
   - Batting average: .342
   - 25 games played
   - 48 videos recorded
   ↓
8. Season moves to "Season History"
   ↓
9. User creates "Fall 2025" for next season
```

### Journey 4: View Past Season Stats

```
1. User on dashboard with Fall 2025 active
   ↓
2. Taps season indicator "⚾ Fall 2025 ▼"
   ↓
3. Season Management opens
   ↓
4. Scrolls to "Season History"
   ↓
5. Taps "Spring 2025"
   ↓
6. Season Detail View opens:
   ┌─────────────────────────────────┐
   │ ⚾ Spring 2025                   │
   │ ✓ Archived                       │
   │                                  │
   │ Season Dates                     │
   │ Started: Mar 1, 2025            │
   │ Ended: Jun 15, 2025             │
   │                                  │
   │ Season Stats                     │
   │ Total Games: 25                  │
   │ Total Videos: 48                 │
   │ Highlights: 15                   │
   │                                  │
   │ Batting Statistics               │
   │ Batting Average: .342            │
   │ At Bats: 82                      │
   │ Hits: 28                         │
   │ Home Runs: 6                     │
   │ RBIs: 22                         │
   │                                  │
   │ [Reactivate Season]              │
   │ [Delete Season]                  │
   └─────────────────────────────────┘
```

## UI Components Reference

### 1. SeasonIndicatorView
**Where**: Navigation bars, toolbars, dashboard headers
**Purpose**: Shows active season, tap to manage
**Size**: Compact (fits in toolbar)

```swift
SeasonIndicatorView(athlete: athlete)
```

### 2. SeasonRecommendationBanner
**Where**: Top of dashboard/profile
**Purpose**: Alerts user to season actions needed
**Size**: Full width banner

```swift
let recommendation = SeasonManager.checkSeasonStatus(for: athlete)
SeasonRecommendationBanner(athlete: athlete, recommendation: recommendation)
```

### 3. SeasonManagementView
**Where**: Navigation destination from profile/settings
**Purpose**: Full season management interface
**Size**: Full screen

```swift
NavigationLink {
    SeasonManagementView(athlete: athlete)
} label: {
    Label("Manage Seasons", systemImage: "calendar")
}
```

### 4. CreateSeasonView
**Where**: Sheet presentation
**Purpose**: Create new season form
**Size**: Modal sheet

```swift
.sheet(isPresented: $showingCreateSeason) {
    CreateSeasonView(athlete: athlete)
}
```

### 5. SeasonDetailView
**Where**: Sheet or navigation from season list
**Purpose**: View complete season details and stats
**Size**: Full screen or sheet

```swift
.sheet(item: $selectedSeason) { season in
    NavigationStack {
        SeasonDetailView(season: season, athlete: athlete)
    }
}
```

### 6. CreateFirstSeasonPrompt
**Where**: Onboarding, empty states
**Purpose**: Guides new users to create first season
**Size**: Full screen

```swift
if athlete.seasons.isEmpty {
    CreateFirstSeasonPrompt(athlete: athlete)
}
```

## Color Coding

- **Blue** (🔵) - Active season, primary actions
- **Green** (🟢) - Success, archived seasons (completed)
- **Orange** (🟠) - Warnings, season recommendations
- **Yellow** (🟡) - Highlights, special items
- **Red** (🔴) - Destructive actions (delete)
- **Gray** (⚫) - Inactive, secondary info

## Icons Used

- `calendar` - Season management
- `calendar.badge.plus` - Create season
- `calendar.badge.exclamationmark` - Season warning
- `archivebox` - Archived season
- `figure.baseball` / `figure.softball` - Sport types
- `checkmark.circle.fill` - Completed/Archived
- `star.fill` - Highlights
- `chart.line.uptrend.xyaxis` - Statistics
- `video.fill` - Videos
- `chevron.down` - Dropdown indicator

## Accessibility

All views include:
- ✅ VoiceOver support
- ✅ Dynamic Type support
- ✅ Semantic labels
- ✅ Logical focus order
- ✅ Clear action buttons
- ✅ Confirmation dialogs

## Animation & Haptics

- Season creation: `.success` haptic
- Season archived: `.success` haptic
- Season deleted: `.warning` haptic
- List updates: `withAnimation`
- Sheet presentations: System defaults

## Data Flow Summary

```
User Action
    ↓
SeasonManager (validation, business logic)
    ↓
SwiftData Model (save/update)
    ↓
View Update (@Query observes changes)
    ↓
UI Reflects New State ✅
```

---

This UI flow ensures a smooth, intuitive experience for managing seasons!
