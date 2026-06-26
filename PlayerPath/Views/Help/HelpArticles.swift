//
//  HelpArticles.swift
//  PlayerPath
//
//  Help article content and models
//

import SwiftUI

/// Shared shape for a help article so `HelpArticleDetailView` can render either
/// the athlete `HelpArticle` enum or the coach `CoachHelpArticle` enum.
protocol HelpArticleProtocol {
    var title: String { get }
    var icon: String { get }
    var content: String { get }
}

enum HelpArticle: HelpArticleProtocol {
    case recordingVideos
    case taggingPlays
    case understandingStats
    case managingAthletes
    case seasonTracking
    case gameManagement
    case crossDeviceSync
    case videoStorage
    case exportingData
    case deletingAccount
    case managingPhotos
    case coachSharing

    // Golf variants — shown when the active athlete's pinned sport is golf.
    case recordingVideosGolf
    case scoringGolf
    case golfStats
    case seasonTrackingGolf
    case roundManagementGolf

    var title: String {
        switch self {
        case .recordingVideos: return "Recording Videos"
        case .taggingPlays: return "Tagging Play Results"
        case .understandingStats: return "Understanding Statistics"
        case .managingAthletes: return "Managing Athletes"
        case .seasonTracking: return "Season Tracking"
        case .gameManagement: return "Game Management"
        case .crossDeviceSync: return "Cross-Device Sync"
        case .videoStorage: return "Video Storage"
        case .exportingData: return "Exporting Your Data"
        case .deletingAccount: return "Deleting Your Account"
        case .managingPhotos: return "Managing Photos"
        case .coachSharing: return "Sharing with Coaches"
        case .recordingVideosGolf: return "Recording Videos"
        case .scoringGolf: return "Scoring Your Round"
        case .golfStats: return "Golf Stats"
        case .seasonTrackingGolf: return "Season Tracking"
        case .roundManagementGolf: return "Rounds & Tournaments"
        }
    }

    var icon: String {
        switch self {
        case .recordingVideos: return "video"
        case .taggingPlays: return "tag.fill"
        case .understandingStats: return "chart.bar.fill"
        case .managingAthletes: return "person.fill"
        case .seasonTracking: return "calendar"
        case .gameManagement: return "baseball.diamond.bases"
        case .crossDeviceSync: return "arrow.triangle.2.circlepath"
        case .videoStorage: return "externaldrive.fill"
        case .exportingData: return "arrow.down.doc"
        case .deletingAccount: return "trash"
        case .managingPhotos: return "photo.fill"
        case .coachSharing: return "person.2.fill"
        case .recordingVideosGolf: return "video"
        case .scoringGolf: return "list.bullet.clipboard.fill"
        case .golfStats: return "chart.bar.fill"
        case .seasonTrackingGolf: return "calendar"
        case .roundManagementGolf: return "figure.golf"
        }
    }

    var content: String {
        switch self {
        case .recordingVideos:
            return """
            PlayerPath offers two ways to record videos:

            **Quick Record (Fastest)**
            1. Tap the "Quick Record" button on the Dashboard
            2. Camera opens instantly
            3. Record your at-bat
            4. Tag the play result
            5. Done!

            **Advanced Mode (More Options)**
            1. Go to the Videos tab
            2. Tap the "+" button
            3. Choose "Record Video"
            4. Select video quality settings
            5. Record your at-bat
            6. Optionally trim the video
            7. Tag the play result

            **Tips:**
            • Hold your device steady or use a tripod
            • Record in landscape for better framing
            • Ensure good lighting
            • Videos are limited to 10 minutes
            • High quality uses ~60MB per minute

            **Recording During a Live Game:**
            When a game is marked as "Live," the Quick Record button will automatically link videos to that game.
            """

        case .taggingPlays:
            return """
            After recording a video, you can tag the play result:

            **Available Tags:**
            • Single (1B) - Base hit
            • Double (2B) - Two-base hit
            • Triple (3B) - Three-base hit
            • Home Run (HR) - Over the fence!
            • Walk (BB) - Ball four
            • Strikeout (K) - Strike three
            • Ground Out (GO)
            • Fly Out (FO)

            **How to Tag:**
            1. After recording, the tagging screen appears
            2. Tap the appropriate play result
            3. Video is automatically saved

            **Auto-Highlighting:**
            All hits (1B, 2B, 3B, HR) are automatically marked as highlights for easy access later.

            **Editing Tags:**
            You can change play result tags later by viewing the video in your library and updating the tag.

            **Statistics:**
            Tagged plays are automatically included in your batting statistics.
            """

        case .understandingStats:
            return """
            PlayerPath calculates standard baseball statistics automatically:

            **Batting Average (AVG)**
            • Formula: Hits ÷ At-Bats
            • Example: 15 hits in 50 at-bats = .300
            • Higher is better (elite is .300+)

            **On-Base Percentage (OBP)**
            • Formula: (Hits + Walks + Hit-by-Pitch) ÷ (At-Bats + Walks + Hit-by-Pitch)
            • Measures how often you reach base
            • Higher is better (elite is .400+)

            **Slugging Percentage (SLG)**
            • Formula: Total Bases ÷ At-Bats
            • Measures power hitting
            • Singles = 1 base, Doubles = 2, Triples = 3, Home Runs = 4
            • Higher is better (elite is .500+)

            **On-Base Plus Slugging (OPS)**
            • Formula: OBP + SLG
            • Comprehensive offensive metric
            • Higher is better (elite is .900+)

            **At-Bats vs. Plate Appearances:**
            • At-Bats: Counted for hits and outs
            • Walks are NOT at-bats (but count for OBP)

            **Where to View:**
            • Dashboard: Quick stats card
            • Stats Tab: Detailed statistics
            • Game Detail: Per-game statistics
            """

        case .managingAthletes:
            return """
            Create and manage multiple athlete profiles:

            **Creating an Athlete:**
            1. After signup, you'll be prompted to create your first athlete
            2. Or tap "Manage Athletes" in More tab
            3. Enter the athlete's name
            4. Tap "Create"

            **Switching Athletes:**
            1. Tap the athlete name at the top of the Dashboard
            2. Select a different athlete from the menu
            3. Or tap "Manage Athletes" to add a new one

            **Editing Athlete Info:**
            1. Go to More tab
            2. Tap "Manage Athletes"
            3. Select an athlete
            4. Edit name or other details
            5. Tap "Save"

            **Deleting an Athlete:**
            1. Go to More tab
            2. Tap "Manage Athletes"
            3. Swipe left on an athlete
            4. Tap "Delete"
            5. Confirm deletion

            **Note:** Deleting an athlete permanently removes all their games, videos, and statistics. This action cannot be undone.

            **Cross-Device Access:**
            Athletes automatically sync across your devices. Create an athlete on your iPhone and see it on your iPad!
            """

        case .seasonTracking:
            return """
            Organize your data by baseball/softball seasons:

            **Creating a Season:**
            1. Go to More tab
            2. Tap "Seasons"
            3. Tap "+" to create new season
            4. Enter season name (e.g., "Spring 2026")
            5. Set start date
            6. Choose sport (Baseball or Softball)
            7. Optionally set as active season
            8. Tap "Create"

            **Active Season:**
            • Only one season can be active at a time
            • New games are automatically added to the active season
            • Videos recorded during games are linked to the season

            **Viewing Season Stats:**
            • Tap on a season to view season-specific statistics
            • See total games played
            • View season batting average, slugging, etc.
            • Access all videos from that season

            **Ending a Season:**
            1. Open season detail
            2. Tap "End Season"
            3. Confirm
            4. Season is archived with final statistics

            **Reactivating a Season:**
            If you ended a season by mistake or want to continue it, you can reactivate it from the archived seasons list.
            """

        case .gameManagement:
            return """
            Track individual games and live game progress:

            **Creating a Game:**
            1. Go to Games tab
            2. Tap "+" button
            3. Enter opponent name
            4. Set game date
            5. Optionally mark as "Live" to start tracking now
            6. Tap "Save"

            **Live Game Tracking:**
            • Mark a game as "Live" to activate live tracking
            • Quick Record button automatically links videos to live game
            • Only one game can be live at a time
            • Live games appear at the top of the Dashboard

            **Recording During Games:**
            • When a game is live, all recorded videos are automatically tagged to that game
            • Tag play results as they happen
            • Real-time statistics update

            **Ending a Game:**
            1. Go to Dashboard or Games tab
            2. Find the live game
            3. Swipe or tap menu → "End Game"
            4. Game statistics are finalized
            5. Videos remain linked to the game

            **Game Statistics:**
            Each game tracks:
            • At-bats, hits, walks, strikeouts
            • Per-game batting average
            • All videos from that game
            • Play-by-play results

            **Deleting a Game:**
            Games can be deleted from the Games tab. Videos are NOT deleted—they remain in your library.
            """

        case .crossDeviceSync:
            return """
            Access your data on multiple devices:

            **What Syncs:**
            ✅ Athletes, Seasons, Games
            ✅ Play results and statistics
            ✅ Video metadata (file info, tags, dates)
            ✅ Video files (uploaded to cloud for backup and access)

            **How It Works:**
            1. Sign in with the same account on multiple devices
            2. Data automatically syncs in the background
            3. Changes appear on other devices within seconds
            4. Works offline—syncs when internet is available

            **Sync Status:**
            • Green checkmark = Synced
            • Spinning indicator = Syncing now
            • Warning icon = Sync failed (will retry)

            **Troubleshooting:**
            • Ensure you're signed in on all devices
            • Check internet connection
            • Pull to refresh to force sync
            • Data syncs automatically—no manual action needed
            """

        case .videoStorage:
            return """
            Understanding where your videos are saved:

            **Local Storage:**
            • Videos are saved in the app's secure container on your device
            • Location: App Documents directory (not accessible outside the app)
            • Files use .mov format (high quality)
            • Deleted when you uninstall the app

            **Storage Space:**
            • High quality: ~60MB per minute
            • 10-minute max recording = ~600MB per video
            • Check available storage in iOS Settings → General → iPhone Storage

            **Video Limits:**
            • Maximum 10 minutes per video
            • Maximum file size: 500MB
            • No limit on number of videos (storage permitting)

            **Thumbnails:**
            • Automatically generated at 1 second
            • Saved as .jpg files (~50KB each)
            • Used in video library grid view

            **Cloud Storage:**
            Video files are uploaded to Firebase Storage for cloud backup and cross-device access. This uses your plan's storage quota.

            **Backing Up Videos:**
            To keep a local backup:
            1. Save to Photos app (use share button)
            2. Export to computer via Files app
            3. Use iCloud Photo Library backup

            **Managing Storage:**
            • Delete old videos you don't need
            • Save important videos to Photos app
            • Archive old seasons' videos externally
            • Monitor storage in iOS Settings
            """

        case .exportingData:
            return """
            Download all your data from PlayerPath:

            **What's Included:**
            • All athlete profiles
            • All seasons and games
            • All statistics
            • Video metadata (file names, dates, tags)
            • Account information

            **How to Export:**
            1. Go to More tab
            2. Tap "Export Data"
            3. Wait for export to complete
            4. Tap "Share" to save the file

            **File Format:**
            • JSON format (industry standard)
            • Human-readable text
            • Can be opened in any text editor
            • Import into spreadsheets or databases

            **What to Do with Exported Data:**
            • Keep as a backup
            • Analyze in Excel/Google Sheets
            • Transfer to another service
            • Required for GDPR compliance

            **Videos:**
            Note: Video files are NOT included in the export (they're too large). To backup videos:
            • Save individual videos to Photos app
            • Use Files app to export videos
            • Connect to computer and transfer via iTunes/Finder

            **Privacy:**
            Your exported data is never sent to us. The file is generated locally on your device and stays under your control.

            **Re-importing:**
            Currently, there's no automated way to re-import data. Contact support if you need help migrating data.
            """

        case .deletingAccount:
            return """
            Permanently delete your account and all data:

            **⚠️ WARNING: This action is permanent and cannot be undone.**

            **How to Delete:**
            1. Go to More tab
            2. Scroll to bottom → "Delete Account"
            3. Read the confirmation message carefully
            4. Tap "Delete"
            5. Confirm one more time
            6. Enter your password to verify
            7. Account is immediately deleted

            **What Gets Deleted:**
            ✅ Your account credentials
            ✅ All athlete profiles
            ✅ All seasons, games, and statistics
            ✅ All video metadata
            ✅ Cloud sync data
            ✅ All settings and preferences

            **What Happens to Video Files:**
            • Video files on your device remain until you uninstall the app
            • They're no longer accessible in PlayerPath
            • Save important videos to Photos before deleting account

            **Timeline:**
            • Account deleted immediately
            • Data removed from servers within 30 days
            • Cached data on other devices cleared on next sync

            **Before You Delete:**
            1. Export your data (More → Export Data)
            2. Save important videos to Photos app
            3. Screenshot key statistics if needed
            4. Consider if you truly want to delete everything

            **Alternative: Sign Out**
            If you just want to stop using the app temporarily, sign out instead of deleting your account. Your data will be preserved.

            **Recovery:**
            Once deleted, data CANNOT be recovered. We do not keep backups of deleted accounts.

            **Support:**
            If you're having issues and considering deletion, please contact support first—we may be able to help!
            """

        case .managingPhotos:
            return """
            PlayerPath lets you capture and organize photos alongside your videos:

            **Adding Photos**
            You can add photos two ways:
            1. Go to your profile and tap "Photos"
            2. Tap "+" in the top-right corner
            3. Choose "Take Photo" to use your camera, or "Choose from Library" to import from your photo library
            4. You can import up to 20 photos at once from your library

            **Tagging Photos to Games or Practices**
            After adding a photo, tap it to open the detail view. From there you can:
            • Link it to a game (e.g., action shots from a specific game)
            • Link it to a practice session
            • Add a caption

            **Filtering Photos**
            In the Photos screen, use the filter bar to view:
            • All photos
            • Game photos only
            • Practice photos only

            **Searching Photos**
            Use the search bar to find photos by:
            • Opponent name (for game-linked photos)
            • Caption text

            You can also tap the filter icon to filter by date range or season.

            **Deleting Photos**
            • Swipe left on a photo thumbnail to delete it
            • Or open the photo detail and tap the trash icon

            **Storage:**
            Photos sync to the cloud automatically, just like videos. They back up and appear on your other devices when you're signed in and connected to the internet.
            """

        case .coachSharing:
            return """
            PlayerPath lets you share your videos and stats with coaches:

            **Shared Folders**
            Shared Folders let you share clips directly with a coach:
            1. Go to More tab → "Shared Folders"
            2. Tap "+" to create a new folder
            3. Name the folder (e.g., "Spring 2026 Highlights")
            4. Add videos from your library
            5. Invite your coach by email

            **Inviting a Coach**
            1. Go to More tab → "Shared Folders"
            2. Open a folder and tap "Invite Coach"
            3. Enter your coach's email address
            4. They'll receive an invitation and can sign up for a free Coach account in PlayerPath

            **What Coaches Can See**
            • Videos you've added to the shared folder
            • The tags and results on those clips
            • Game and date information
            • Your statistics for shared clips

            **What Coaches Cannot See**
            • Videos not added to shared folders
            • Your account information
            • Other athletes' data

            **Coach Feedback**
            Coaches can leave notes on your videos and mark up frames with drawings. You'll receive a notification when feedback is added.

            **Removing Access**
            To revoke a coach's access, open the shared folder, tap the coach's name, and tap "Remove Access."
            """

        case .recordingVideosGolf:
            return """
            PlayerPath offers two ways to record videos:

            **Quick Record (Fastest)**
            1. Tap "Quick Record" on the Dashboard
            2. The camera opens instantly
            3. Record your swing
            4. It's saved to your library

            **Advanced Mode (More Options)**
            1. Go to the Videos tab
            2. Tap the "+" button
            3. Choose "Record Video"
            4. Pick your quality settings
            5. Record a swing or a full range session
            6. Optionally trim before saving

            **Recording During a Round:**
            While a round is open, use the hole stepper to tag clips to the hole you're playing, so your swings stay organized by hole.

            **Auto Highlight Reels:**
            Post a birdie or better in a round and PlayerPath automatically bundles that round's clips into a highlight reel — no setup needed.

            **Tips:**
            • Film down-the-line and face-on for the most useful swing review
            • Hold the device steady or use a tripod
            • Use slow motion for mechanics when your camera supports it
            • Videos are limited to 10 minutes
            """

        case .scoringGolf:
            return """
            Track every round hole-by-hole — and go as deep as you like.

            **Starting a Round**
            1. Go to the Rounds tab
            2. Tap "+" to start a round
            3. Pick your course (par and hole info prefill when available)
            4. Set the date

            **Per-Hole Scoring**
            For each hole, enter:
            • Score (strokes)
            • Putts
            • Fairway hit — FIR (par 4s and 5s)
            • Green in regulation — GIR
            Your score to par updates live as you play.

            **Shot-by-Shot Tracking (Optional)**
            Want more detail? Turn on shot tracking for a hole and log each shot's lie, club, and distance. It's completely opt-in — score-only rounds work great, and shot tracking simply unlocks deeper stats (estimated driving distance, tee-miss and approach patterns, sand saves) when you want them.

            **Practice Rounds**
            Rounds you log as practice still count toward your stats, so range days and casual rounds build the same picture as tournament rounds.

            **Editing**
            Tap any hole to fix a score, add putts, or toggle FIR/GIR later — your stats recalculate automatically.
            """

        case .golfStats:
            return """
            PlayerPath turns the rounds you log into golf statistics automatically:

            **Scoring**
            • Scoring average across your rounds
            • Score to par, per round and overall
            • Handicap estimate — calculated from your recent rounds (an estimate, not an official USGA Handicap Index)

            **Accuracy**
            • Fairways in Regulation (FIR) — how often you find the fairway off the tee on par 4s and 5s
            • Greens in Regulation (GIR) — how often you reach the green in regulation
            • Putts per round

            **From Shot Tracking**
            When you log shots on a hole, you also unlock:
            • Estimated driving distance (an estimate — it reads long on doglegs)
            • Tee-miss tendency (left vs. right)
            • Approach miss pattern (short / long / left / right / bunker)
            • Sand saves

            Score-only rounds still give you scoring, FIR, GIR, and putts — shot stats just need shot-by-shot tracking turned on.

            **Where to View:**
            • Stats tab → Golf
            • Round detail for a single round's breakdown

            All of these stats are descriptive and free, and they update as you log more rounds.
            """

        case .seasonTrackingGolf:
            return """
            Organize your rounds and videos by golf season:

            **Creating a Season:**
            1. Go to More tab → Seasons
            2. Tap "+" to create a new season
            3. Enter a name (e.g., "2026 Season")
            4. Set the start date
            5. Choose Golf as the sport
            6. Optionally make it your active season
            7. Tap "Create"

            **Active Season:**
            • Only one season is active at a time
            • New rounds automatically join the active season
            • Clips you record during rounds link to the season too

            **Viewing Season Stats:**
            • Tap a season to see season-specific golf stats
            • Scoring average, FIR, GIR, and putts for the season
            • Every round and video from that season in one place

            **Ending a Season:**
            1. Open the season detail
            2. Tap "End Season"
            3. It's archived with its final stats — reactivate any time from the archived list
            """

        case .roundManagementGolf:
            return """
            Track individual rounds and group them into tournaments:

            **Rounds**
            A round is a single trip around the course. To create one:
            1. Go to the Rounds tab
            2. Tap "+"
            3. Pick the course and date
            4. Score it hole-by-hole (see "Scoring Your Round")

            **Tournaments**
            A tournament groups multiple rounds together — perfect for a multi-day event:
            1. Create a tournament
            2. Link your rounds to it
            3. See combined scoring across all rounds

            **Deleting a Tournament**
            Deleting a tournament only *unlinks* its rounds — the rounds themselves, with all their scores and videos, are kept. Nothing is lost.

            **Practice vs. Tournament Rounds**
            Mark a round as a practice round to keep range days separate from competitive rounds. Both still feed your stats.

            **Videos**
            Clips recorded during a round stay linked to it. Delete a round and its videos remain in your library.
            """
        }
    }
}

struct HelpArticleDetailView<Article: HelpArticleProtocol>: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: article.icon)
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.brandNavy)
                        .cornerRadius(12)

                    Text(article.title)
                        .font(.displayLarge)
                }
                .padding(.top)

                Divider()

                // Content
                Text(article.content)
                    .font(.bodyLarge)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HelpArticleDetailView(article: HelpArticle.recordingVideos)
    }
}
