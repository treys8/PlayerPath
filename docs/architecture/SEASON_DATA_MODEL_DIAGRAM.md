# Season Management Data Model Diagram

## Entity Relationship Diagram

```
┌──────────────────────────────┐
│            User              │
│                              │
│ • id: UUID                  │
│ • username                  │
│ • email                     │
│ • subscriptionTier          │
│   (free / plus / pro)       │
│ • coachSubscriptionTier      │
│   (free/instructor/          │
│    proInstructor/academy)   │
└─────────┬────────────────────┘
          │ 1
          │ has many
          │ n
┌─────────▼──────────┐
│      Athlete       │
│                    │
│ • id: UUID        │
│ • name            │
│ • createdAt       │
└─────────┬──────────┘
          │ 1
          │ has many
          │ n
┌─────────▼──────────────────────────────┐
│              Season                     │
│                                         │
│ • id: UUID                             │
│ • name: String                         │
│ • startDate: Date                      │
│ • endDate: Date?                       │
│ • isActive: Bool                       │◄── Only ONE active per athlete
│ • sport: SportType                     │
│   (baseball / softball / golf)         │
│ • notes: String                        │
└──────┬────────┬─────────┬───────────────┘
       │        │         │
       │        │         │ has many
       │        │         ▼
       │        │       ┌────────────────────┐
       │        │       │     Practice       │
       │        │       │                    │
       │        │       │ • date             │
       │        │       │ • notes            │
       │        │       └─────────┬──────────┘
       │        │                 │ has many (golf practice rounds, XOR w/ Game)
       │        │                 ▼
       │        │           [ HoleScore ] ── see golf hierarchy below
       │        │
       │        │ has many
       │        ▼
       │      ┌─────────────────────────────┐
       │      │            Game             │
       │      │  (golf: a "Round")          │
       │      │                             │
       │      │ • date                      │
       │      │ • opponent                  │
       │      │ • isLive                    │
       │      │ • isComplete                │
       │      │ • tournament: GolfTournament? │◄─ golf only (optional)
       │      │ • roundNumber: Int?         │◄─ golf only
       │      └───┬─────────────────────┬───┘
       │          │ has one             │ has many (golf, XOR w/ Practice)
       │          ▼                     ▼
       │   ┌────────────────────┐  [ HoleScore ] ── see golf hierarchy below
       │   │  GameStatistics    │
       │   │                    │
       │   │ • atBats           │
       │   │ • hits             │
       │   │ • homeRuns         │
       │   │ • rbis             │
       │   │ • strikeouts       │
       │   └────────────────────┘
       │
       │ has many
       ▼
┌────────────────────┐
│    VideoClip       │
│                    │
│ • fileName         │
│ • filePath         │
│ • cloudURL         │
│ • isHighlight      │
│ • isUploaded       │
└─────────┬──────────┘
          │ has one
          ▼
┌────────────────────┐
│    PlayResult      │
│                    │
│ • type             │
│   (single, double, │
│    homerun, etc.)  │
└────────────────────┘
```

## Golf Hierarchy (separate from Season)

Golf reuses `Game` (a golf Game **is** a "Round") and `Practice` (a practice round),
but adds three @Model entities. **`GolfTournament` is NOT a child of `Season`** — it
hangs off `Athlete` directly and sits *above* `Game`, grouping several rounds (the
same way `Season` sits above `Game`). A golf round may belong to a tournament OR stand
alone; deleting a tournament **UNLINKS** its rounds (clears `tournament`/`roundNumber`),
it never cascade-deletes them.

```
┌────────────────────┐
│      Athlete       │
└─────────┬──────────┘
          │ has many                       has many (virtual birdie reels)
          ▼                                          │
┌──────────────────────────────┐                    ▼
│       GolfTournament         │          ┌────────────────────┐
│                              │          │   HighlightReel    │
│ • id: UUID                  │          │  (virtual reel)    │
│ • name                      │          │                    │
│ • location                  │          │ • athleteID        │
│ • startDate / endDate       │          │ • ordered clip refs│
│ • notes                     │          │   (birdie-or-better│
└─────────┬────────────────────┘          │    holes w/ clips) │
          │ has many (rounds)             └────────────────────┘
          │ inverse = Game.tournament
          ▼
┌──────────────────────────────┐
│      Game  (a "Round")       │
│  tournament?, roundNumber?   │
└─────────┬────────────────────┘
          │ has many (XOR: a HoleScore attaches to a Game OR a Practice)
          ▼
┌──────────────────────────────┐
│         HoleScore            │
│                              │
│ • holeNumber: Int           │
│ • par / score / putts       │
│ • fairwayHit?               │
│ • greenInRegulation?        │
│ • penalties?                │
│ • game? / practice? (XOR)   │
└─────────┬────────────────────┘
          │ has many (cascade delete)
          ▼
┌──────────────────────────────┐
│            Shot              │
│  (shot-by-shot rows for      │
│   rounds in shot-track mode) │
└──────────────────────────────┘
```

## Season Lifecycle States

```
┌──────────────────────────────────────────────────────┐
│                  SEASON STATES                        │
└──────────────────────────────────────────────────────┘

State 1: CREATED
┌────────────────────┐
│ isActive = false   │
│ startDate = set    │
│ endDate = nil      │
└────────────────────┘
        ↓
        │ activate()
        ↓
State 2: ACTIVE (only one per athlete)
┌────────────────────┐
│ isActive = true    │◄─── All new items link here
│ startDate = set    │
│ endDate = nil      │
└────────────────────┘
        ↓
        │ archive()
        ↓
State 3: ARCHIVED
┌────────────────────┐
│ isActive = false   │
│ startDate = set    │
│ endDate = set      │
│ stats calculated   │
└────────────────────┘
        ↓
        │ activate() (can reactivate)
        ↓
     Back to ACTIVE
```

## Data Flow - Creating a Game

```
User creates game
      ↓
Game object created
      ↓
game.athlete = athlete
      ↓
SeasonManager.linkGameToActiveSeason()
      ↓
      ├─ No active season? → Create "Spring 2025" automatically
      │                       Activate it
      │                       ↓
      └─────────────────────→ game.season = activeSeason
                              activeSeason.games.append(game)
      ↓
Save to SwiftData
      ↓
UI automatically updates (@Query observes)
      ↓
Game appears in season!
```

## Season Organization Example

```
Athlete: "Sarah Johnson"
│
├─ Season: Spring 2025 (ACTIVE) ✅
│  ├─ Games (12)
│  │  ├─ vs Panthers (Mar 15) - W 5-3
│  │  ├─ vs Wildcats (Mar 22) - L 2-4
│  │  └─ ...
│  ├─ Practices (8)
│  │  ├─ Hitting practice (Mar 10)
│  │  ├─ Fielding drills (Mar 17)
│  │  └─ ...
│  ├─ Videos (45)
│  │  ├─ Home run vs Panthers
│  │  ├─ Batting practice - cage
│  │  └─ ...
│  └─ Statistics
│     ├─ BA: .342
│     ├─ HR: 6
│     └─ RBI: 18
│
├─ Season: Fall 2024 (ARCHIVED) 📦
│  ├─ Games (18)
│  ├─ Practices (12)
│  ├─ Videos (52)
│  └─ Statistics
│     ├─ BA: .318
│     ├─ HR: 8
│     └─ RBI: 22
│
└─ Season: Spring 2024 (ARCHIVED) 📦
   ├─ Games (15)
   ├─ Practices (10)
   ├─ Videos (38)
   └─ Statistics
      ├─ BA: .295
      ├─ HR: 4
      └─ RBI: 15
```

## Key Relationships Summary

| Entity | Relationship | Entity | Type |
|--------|--------------|--------|------|
| User | has many | Athlete | 1:n |
| Athlete | has many | Season | 1:n |
| Athlete | has one active | Season | 1:1 |
| Season | has many | Game | 1:n |
| Season | has many | Practice | 1:n |
| Season | has many | VideoClip | 1:n |
| Season | has one | AthleteStatistics | 1:1 |
| Game | belongs to | Season | n:1 |
| Game | has one | GameStatistics | 1:1 |
| VideoClip | belongs to | Season | n:1 |
| VideoClip | has one | PlayResult | 1:1 |
| Athlete | has many | GolfTournament | 1:n (golf — NOT under Season) |
| Athlete | has many | HighlightReel | 1:n (golf — virtual birdie reels) |
| GolfTournament | groups (has many) | Game (Round) | 1:n (optional; delete UNLINKS) |
| Game (Round) | belongs to | GolfTournament | n:1 (optional) |
| Game / Practice | has many | HoleScore | 1:n (golf — XOR parent) |
| HoleScore | has many | Shot | 1:n (golf — cascade delete) |

## Important Constraints

1. **Only ONE active season per athlete**
   - When activating a season, previous active is archived
   - `athlete.activeSeason` returns the currently active one

2. **Items auto-link to active season**
   - New games → active season
   - New practices → active season
   - New videos → active season
   - Uses `SeasonManager` utilities

3. **Statistics snapshot on archive**
   - When season ends, stats are calculated
   - Aggregates all GameStatistics
   - Saved in `season.seasonStatistics`

4. **Season can be reactivated**
   - Archived seasons can become active again
   - Useful for making corrections

## SwiftData Schema

```swift
@Model
final class Season {
    var id: UUID
    var name: String = ""
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool = false
    var createdAt: Date?
    var sport: SportType = .baseball
    var notes: String = ""
    
    // Relationships
    var athlete: Athlete?
    var games: [Game] = []
    var practices: [Practice] = []
    var videoClips: [VideoClip] = []
    var seasonStatistics: AthleteStatistics?
    // Note: golf tournaments are NOT a Season relationship — GolfTournament
    // hangs off Athlete (Athlete.golfTournaments) and sits above Game.
    
    // Computed properties
    var displayName: String { /* ... */ }
    var isArchived: Bool { /* ... */ }
    var totalGames: Int { /* ... */ }
    var totalVideos: Int { /* ... */ }
    var highlights: [VideoClip] { /* ... */ }
}
```

## Query Examples

### Get Active Season
```swift
if let activeSeason = athlete.activeSeason {
    print("Current: \(activeSeason.displayName)")
}
```

### Get All Archived Seasons
```swift
let archived = athlete.archivedSeasons // Sorted by date descending
```

### Get Games for Active Season
```swift
let games = athlete.activeSeason?.games ?? []
```

### Get All Videos from a Specific Season
```swift
let videos = season.videoClips
let highlights = season.highlights // Only highlight videos
```

### Get Season Statistics
```swift
if let stats = season.seasonStatistics {
    let ba = stats.battingAverage
    let hr = stats.homeRuns
}
```

## Migration Example

### Before Migration
```
Athlete: "Mike"
├─ Games (50) ← No season link
├─ Practices (30) ← No season link
└─ Videos (120) ← No season link
```

### After Migration
```
Athlete: "Mike"
│
├─ Season: Spring 2025 (ACTIVE)
│  ├─ Games (15) ← Recent games
│  ├─ Practices (12)
│  └─ Videos (40)
│
├─ Season: Fall 2024
│  ├─ Games (18)
│  ├─ Practices (10)
│  └─ Videos (45)
│
└─ Season: Spring 2024
   ├─ Games (17)
   ├─ Practices (8)
   └─ Videos (35)
```

All data automatically grouped by date and linked! 🎉

## Performance Considerations

### Efficient Queries
```swift
// ✅ GOOD: Filter by season first
let seasonGames = activeSeason.games.filter { $0.isComplete }

// ❌ AVOID: Loading all games then filtering
let allGames = athlete.games // Could be hundreds
let filtered = allGames.filter { /* ... */ }
```

### Cascade Deletes
When deleting a season, you can:
1. **Unlink items** (keep games/videos, just remove season reference)
2. **Cascade delete** (delete season AND all items)

Current implementation: **Unlinks** by default (safer)

---

This diagram shows how all the pieces fit together in the Season Management system!
