# Season Management System Documentation

## Overview

The Season Management System allows athletes to organize their baseball/softball journey by season. All games, practices, videos, and statistics are grouped by season, keeping the app organized and providing a clean year-by-year history.

## Key Concepts

### Season Model
- **Active Season**: Only ONE season per athlete can be active at a time
- **Archived Seasons**: Previous seasons that have been ended
- **Season Types**: Baseball or Softball
- **Season Statistics**: Automatically calculated when season is archived

### Data Organization
```
Athlete
├── Season (Spring 2025) - ACTIVE
│   ├── Games
│   ├── Practices
│   ├── Videos
│   ├── Tournaments
│   └── Statistics
│
├── Season (Fall 2024) - ARCHIVED
│   ├── Games
│   ├── Practices
│   ├── Videos
│   ├── Tournaments
│   └── Statistics
│
└── Season (Spring 2024) - ARCHIVED
    └── ...
```

## Files Created

### 1. **Models.swift** (Updated)
- Added `Season` model with relationships
- Updated `Athlete`, `Game`, `Practice`, `VideoClip`, `Tournament` to include season relationships
- Added computed properties for active/archived seasons

### 2. **SeasonManagementView.swift**
Complete UI for managing seasons:
- **SeasonManagementView**: Main view for season overview
- **CreateSeasonView**: Form to create new seasons
- **SeasonDetailView**: Detailed view of a season with stats
- **ActiveSeasonCard**: Visual card showing current season
- **SeasonHistoryRow**: Row for archived seasons

### 3. **SeasonManager.swift**
Utility functions for season management:
- `ensureActiveSeason()`: Auto-creates default season if needed
- `linkGameToActiveSeason()`: Links game to active season
- `linkPracticeToActiveSeason()`: Links practice to active season
- `linkVideoToActiveSeason()`: Links video to active season
- `linkTournamentToActiveSeason()`: Links tournament to active season
- `generateSeasonSummary()`: Creates formatted summary
- `checkSeasonStatus()`: Recommends season actions

### 4. **SeasonIndicatorView.swift**
UI components for showing season status:
- **SeasonIndicatorView**: Compact season indicator (use in nav bars)
- **SeasonRecommendationBanner**: Shows season recommendations
- **CreateFirstSeasonPrompt**: Full-page prompt for first season

### 5. **SeasonMigrationHelper.swift**
Handles migration of existing data:
- `migrateExistingData()`: Migrates all existing data to seasons
- `needsMigration()`: Checks if migration is needed
- Intelligently groups data by date into appropriate seasons

## Integration Guide

### Step 1: Add Season Indicator to Dashboard/Profile

In your main athlete view (Dashboard, Profile, etc.), add the season indicator:

```swift
struct AthleteView: View {
    let athlete: Athlete
    
    var body: some View {
        VStack {
            // Add at the top
            SeasonIndicatorView(athlete: athlete)
                .padding()
            
            // Rest of your content
        }
    }
}
```

### Step 2: Add Season Recommendations

Show recommendations when appropriate:

```swift
struct DashboardView: View {
    let athlete: Athlete
    
    var body: some View {
        VStack {
            let recommendation = SeasonManager.checkSeasonStatus(for: athlete)
            SeasonRecommendationBanner(athlete: athlete, recommendation: recommendation)
                .padding()
            
            // Rest of content
        }
    }
}
```

### Step 3: Link New Items to Active Season

When creating games, practices, or videos, automatically link them:

```swift
// When creating a game
func createGame(opponent: String, date: Date, athlete: Athlete) {
    let game = Game(date: date, opponent: opponent)
    game.athlete = athlete
    athlete.games.append(game)
    
    // Link to active season
    SeasonManager.linkGameToActiveSeason(game, for: athlete, in: modelContext)
    
    modelContext.insert(game)
    try? modelContext.save()
}

// When creating a practice
func createPractice(date: Date, athlete: Athlete) {
    let practice = Practice(date: date)
    practice.athlete = athlete
    athlete.practices.append(practice)
    
    // Link to active season
    SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
    
    modelContext.insert(practice)
    try? modelContext.save()
}

// When recording a video
func saveVideo(fileName: String, filePath: String, athlete: Athlete) {
    let video = VideoClip(fileName: fileName, filePath: filePath)
    video.athlete = athlete
    athlete.videoClips.append(video)
    
    // Link to active season
    SeasonManager.linkVideoToActiveSeason(video, for: athlete, in: modelContext)
    
    modelContext.insert(video)
    try? modelContext.save()
}
```

### Step 4: Handle Migration for Existing Users

Add migration check when app loads or athlete is selected:

```swift
struct AthleteDetailView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var hasMigrated = false
    
    var body: some View {
        VStack {
            // Your content
        }
        .task {
            if !hasMigrated && SeasonMigrationHelper.needsMigration(for: athlete) {
                await SeasonMigrationHelper.migrateExistingData(for: athlete, in: modelContext)
                hasMigrated = true
            }
        }
    }
}
```

### Step 5: Add Season Management to Profile/Settings

Add navigation to Season Management:

```swift
Section("Organization") {
    NavigationLink {
        SeasonManagementView(athlete: athlete)
    } label: {
        Label("Manage Seasons", systemImage: "calendar")
    }
}
```

### Step 6: Filter Views by Season

Update your game/video/practice lists to filter by active season:

```swift
struct GamesView: View {
    let athlete: Athlete
    
    var filteredGames: [Game] {
        if let activeSeason = athlete.activeSeason {
            // Show only active season games by default
            return athlete.games.filter { $0.season?.id == activeSeason.id }
        }
        return athlete.games
    }
    
    var body: some View {
        List(filteredGames) { game in
            GameRow(game: game)
        }
    }
}
```

## Usage Examples

### Creating a Season
```swift
let season = Season(name: "Spring 2025", startDate: Date(), sport: .baseball)
season.activate() // Makes it the active season
season.athlete = athlete
athlete.seasons.append(season)
modelContext.insert(season)
```

### Ending a Season
```swift
season.archive() // Sets endDate and calculates stats
season.isActive = false
```

### Getting Active Season
```swift
if let activeSeason = athlete.activeSeason {
    print("Current season: \(activeSeason.displayName)")
}
```

### Getting Season Stats
```swift
if let stats = season.seasonStatistics {
    print("BA: \(stats.battingAverage)")
    print("Games: \(season.totalGames)")
}
```

## Best Practices

1. **Always Use SeasonManager**: Don't manually create/link seasons - use SeasonManager utilities
2. **One Active Season**: Enforce only one active season per athlete
3. **Auto-Create If Needed**: Use `ensureActiveSeason()` to create default season if none exists
4. **Prompt Users**: Use `SeasonRecommendationBanner` to guide users
5. **Archive Old Seasons**: Remind users to end seasons that are 6+ months old
6. **Migration**: Run migration check once per athlete on first load
7. **Filter by Season**: Default to showing active season data, with option to view all

## Subscription Tier Considerations

### Free Tier
- 1 athlete
- Unlimited seasons
- Can create/archive seasons

### Pro Tier
- Up to 3 athletes
- Unlimited seasons per athlete
- Season statistics

### Premium Tier
- Unlimited athletes
- Unlimited seasons
- Advanced season analytics
- Export season summaries
- Season-to-season comparisons

## Future Enhancements

1. **Season Templates**: Save season structure (teams, positions) to reuse
2. **Season Goals**: Set and track goals per season
3. **Season Comparison**: Compare stats across seasons
4. **Season Reports**: Generate PDF reports with highlights
5. **Season Sharing**: Share season summaries with coaches
6. **Multi-Sport Seasons**: Support overlapping seasons for different sports
7. **Season Calendar**: Visual calendar view of season schedule

## Testing Checklist

- [ ] Create first season for new athlete
- [ ] Create multiple seasons for one athlete
- [ ] Activate different seasons
- [ ] Archive a season
- [ ] View season details
- [ ] Delete a season
- [ ] Link games to seasons automatically
- [ ] Link practices to seasons automatically
- [ ] Link videos to seasons automatically
- [ ] Migration of existing data
- [ ] Season statistics calculation
- [ ] Season filtering in lists
- [ ] Season indicator UI
- [ ] Season recommendations

## Troubleshooting

### Issue: Games not showing up
**Solution**: Ensure games are linked to active season or check season filter

### Issue: Multiple active seasons
**Solution**: Use `season.activate()` which should deactivate others (add logic if needed)

### Issue: Migration not working
**Solution**: Check `needsMigration()` returns true and dates exist on items

### Issue: Season stats not calculating
**Solution**: Ensure `season.archive()` is called, which calculates stats from games

---

## Quick Reference

### Key Properties
- `athlete.activeSeason` - Currently active season
- `athlete.archivedSeasons` - All past seasons
- `season.isActive` - Is this season active?
- `season.isArchived` - Is this season ended?
- `season.totalGames` - Number of completed games
- `season.totalVideos` - Number of videos
- `season.highlights` - All highlight videos

### Key Methods
- `season.activate()` - Make season active
- `season.archive(endDate:)` - End season and calculate stats
- `SeasonManager.ensureActiveSeason()` - Get or create active season
- `SeasonManager.linkGameToActiveSeason()` - Link game to active season
- `SeasonMigrationHelper.migrateExistingData()` - Migrate old data
