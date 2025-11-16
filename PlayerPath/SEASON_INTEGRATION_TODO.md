# Season Management Integration TODO

## Overview
You previously built a complete season management system, but it hasn't been fully integrated into the main app yet. This document outlines exactly what needs to be done in each file.

## ✅ Completed

### MainAppView.swift
- [x] Added season indicator to Dashboard
- [x] Added season recommendations banner  
- [x] Added migration check on dashboard load

## 🔲 TODO: Critical Integrations

### 1. **GamesView.swift** - Link games to active season

When creating a new game, add this line AFTER inserting the game:

```swift
// In your createGame() or addGame() function:
func createGame() {
    let newGame = Game(date: gameDate, opponent: opponent)
    newGame.athlete = athlete
    athlete.games.append(newGame)
    modelContext.insert(newGame)
    
    // ✅ ADD THIS LINE:
    SeasonManager.linkGameToActiveSeason(newGame, for: athlete, in: modelContext)
    
    try? modelContext.save()
}
```

**Optional Enhancement: Add Season Filter**
Add a toggle to show all games or just current season games:

```swift
struct GamesView: View {
    let athlete: Athlete
    @State private var showAllSeasons = false
    
    private var filteredGames: [Game] {
        if showAllSeasons {
            return athlete.games.sorted(by: { /* ... */ })
        } else if let activeSeason = athlete.activeSeason {
            return athlete.games
                .filter { $0.season?.id == activeSeason.id }
                .sorted(by: { /* ... */ })
        }
        return athlete.games.sorted(by: { /* ... */ })
    }
    
    var body: some View {
        List {
            // Add filter toggle at top
            Section {
                Toggle("Show All Seasons", isOn: $showAllSeasons)
            }
            
            // Use filteredGames instead of athlete.games
            ForEach(filteredGames) { game in
                // ... game rows
            }
        }
    }
}
```

---

### 2. **VideoClipsView.swift** - Link videos to active season

When saving a video (after recording or uploading), add this:

```swift
// In your saveVideo() or similar function:
func saveVideo(filePath: String, fileName: String) {
    let video = VideoClip(fileName: fileName, filePath: filePath)
    video.athlete = athlete
    video.createdAt = Date()
    athlete.videoClips.append(video)
    modelContext.insert(video)
    
    // ✅ ADD THIS LINE:
    SeasonManager.linkVideoToActiveSeason(video, for: athlete, in: modelContext)
    
    try? modelContext.save()
}
```

**Optional Enhancement: Add Season Filter**

```swift
struct VideoClipsView: View {
    let athlete: Athlete
    @State private var showAllSeasons = false
    
    private var filteredVideos: [VideoClip] {
        if showAllSeasons {
            return athlete.videoClips.sorted(by: { /* ... */ })
        } else if let activeSeason = athlete.activeSeason {
            return athlete.videoClips
                .filter { $0.season?.id == activeSeason.id }
                .sorted(by: { /* ... */ })
        }
        return athlete.videoClips.sorted(by: { /* ... */ })
    }
    
    var body: some View {
        VStack {
            // Add filter toggle
            Toggle("Show All Seasons", isOn: $showAllSeasons)
                .padding()
            
            // Use filteredVideos
            ScrollView {
                ForEach(filteredVideos) { video in
                    // ... video cards
                }
            }
        }
    }
}
```

---

### 3. **PracticesView.swift** - Link practices to active season

When creating a practice, add:

```swift
// In your createPractice() function:
func createPractice() {
    let newPractice = Practice(date: practiceDate)
    newPractice.athlete = athlete
    athlete.practices.append(newPractice)
    modelContext.insert(newPractice)
    
    // ✅ ADD THIS LINE:
    SeasonManager.linkPracticeToActiveSeason(newPractice, for: athlete, in: modelContext)
    
    try? modelContext.save()
}
```

---

### 4. **StatisticsView.swift** - Filter stats by season

This is more involved since stats need to be calculated per season:

```swift
struct StatisticsView: View {
    let athlete: Athlete
    @State private var selectedSeason: Season?
    
    // Stats for selected season or all time
    private var displayedStats: Statistics? {
        if let season = selectedSeason {
            return season.seasonStatistics
        } else {
            return athlete.statistics // All-time stats
        }
    }
    
    var body: some View {
        List {
            // Season Picker
            Section {
                Picker("Season", selection: $selectedSeason) {
                    Text("All Time").tag(nil as Season?)
                    
                    if let active = athlete.activeSeason {
                        Text(active.displayName).tag(active as Season?)
                    }
                    
                    ForEach(athlete.archivedSeasons) { season in
                        Text(season.displayName).tag(season as Season?)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Filter by Season")
            }
            
            // Use displayedStats instead of athlete.statistics
            if let stats = displayedStats {
                Section("Batting Statistics") {
                    LabeledContent("Batting Average", value: String(format: ".%.3d", Int(stats.battingAverage * 1000)))
                    LabeledContent("Hits", value: "\(stats.hits)")
                    LabeledContent("At Bats", value: "\(stats.atBats)")
                    // ... etc
                }
            } else {
                Text("No statistics available")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Statistics")
    }
}
```

---

### 5. **ProfileView.swift or MoreView.swift** - Add Season Management link

Add this to your settings/profile section:

```swift
// In your settings section:
Section("Organization") {
    NavigationLink {
        SeasonManagementView(athlete: selectedAthlete)
    } label: {
        Label("Manage Seasons", systemImage: "calendar")
    }
    
    // Your other settings...
}
```

---

### 6. **TournamentsView.swift** - Link tournaments to active season

When creating a tournament:

```swift
func createTournament() {
    let tournament = Tournament(name: tournamentName, startDate: startDate)
    tournament.athlete = athlete
    athlete.tournaments.append(tournament)
    modelContext.insert(tournament)
    
    // ✅ ADD THIS LINE:
    SeasonManager.linkTournamentToActiveSeason(tournament, for: athlete, in: modelContext)
    
    try? modelContext.save()
}
```

---

## 🎯 Priority Order

### Must Do Now (Core Functionality)
1. ✅ **MainAppView.swift** - Season indicator and migration *(DONE)*
2. 🔲 **GamesView.swift** - Link new games to season
3. 🔲 **VideoClipsView.swift** - Link new videos to season  
4. 🔲 **PracticesView.swift** - Link new practices to season
5. 🔲 **ProfileView/MoreView.swift** - Add Season Management navigation

### Should Do Soon (Better UX)
6. 🔲 **GamesView.swift** - Add season filter toggle
7. 🔲 **VideoClipsView.swift** - Add season filter toggle
8. 🔲 **StatisticsView.swift** - Add season filtering with picker
9. 🔲 **TournamentsView.swift** - Link tournaments to season

### Nice to Have (Polish)
10. 🔲 Show season badge on game/video cards
11. 🔲 Add season info to detail views
12. 🔲 Season comparison feature
13. 🔲 Season export/sharing

---

## Testing Checklist

After making these changes, test:

- [ ] Create new athlete - should auto-create first season
- [ ] Create new game - should link to active season
- [ ] Record new video - should link to active season
- [ ] Create new practice - should link to active season
- [ ] View Season Management - should show active and archived seasons
- [ ] Filter games by season - should show only current season games
- [ ] Filter videos by season - should show only current season videos
- [ ] View stats by season - should calculate per-season stats
- [ ] Create new season - should archive old one and activate new one
- [ ] Migrate existing data - should create appropriate seasons

---

## Common Issues

### Issue: "SeasonManager not found"
**Solution:** Make sure `SeasonManager.swift` is included in your Xcode target.

### Issue: "SeasonIndicatorView not found"  
**Solution:** Make sure `SeasonIndicatorView.swift` is included in your Xcode target.

### Issue: Games not showing in season
**Solution:** Check that `SeasonManager.linkGameToActiveSeason()` is being called after creating games.

### Issue: Migration not working
**Solution:** Check that athlete has games/videos with valid dates. Migration groups by date.

---

## Quick Reference

### Key Functions to Use

```swift
// Get or create active season
SeasonManager.ensureActiveSeason(for: athlete, in: modelContext)

// Link items to active season
SeasonManager.linkGameToActiveSeason(game, for: athlete, in: modelContext)
SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
SeasonManager.linkVideoToActiveSeason(video, for: athlete, in: modelContext)
SeasonManager.linkTournamentToActiveSeason(tournament, for: athlete, in: modelContext)

// Check if migration needed
SeasonMigrationHelper.needsMigration(for: athlete)

// Perform migration
await SeasonMigrationHelper.migrateExistingData(for: athlete, in: modelContext)

// Get season recommendation
let recommendation = SeasonManager.checkSeasonStatus(for: athlete)
```

### Key Computed Properties

```swift
athlete.activeSeason         // Current active season (or nil)
athlete.archivedSeasons      // All past seasons
athlete.seasons              // All seasons

season.totalGames            // Number of games in season
season.totalVideos           // Number of videos in season
season.highlights            // Highlight videos in season
season.isActive              // Is this the active season?
season.isArchived            // Is this season ended?
season.seasonStatistics      // Stats snapshot for archived season
```

---

## Next Steps

1. **Start with GamesView.swift** - Add the one line to link games to seasons
2. **Then VideoClipsView.swift** - Add the one line to link videos to seasons
3. **Then PracticesView.swift** - Add the one line to link practices to seasons
4. **Then ProfileView/MoreView.swift** - Add navigation to Season Management
5. **Test** - Create a game and verify it's linked to the active season
6. **Add filters** - Once linking works, add the season filter toggles

The linking changes are literally just **one line per view**, so it's very quick to integrate!

---

## Questions?

- **Q: Do I need to change my models?**  
  A: No! The Season relationships are already in your Models.swift file.

- **Q: What if users don't want to use seasons?**  
  A: The system auto-creates a default season silently. They never have to manage it if they don't want to.

- **Q: Will this break existing data?**  
  A: No! The migration system will automatically organize existing data into appropriate seasons.

- **Q: Can I test this without breaking my data?**  
  A: Yes! Test in the simulator first, or use a test athlete profile.
