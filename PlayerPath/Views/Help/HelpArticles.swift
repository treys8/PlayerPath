//
//  HelpArticles.swift
//  PlayerPath
//
//  Help article content and models
//

import SwiftUI

enum HelpArticle {
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
        }
    }

    var icon: String {
        switch self {
        case .recordingVideos: return "video.fill"
        case .taggingPlays: return "tag.fill"
        case .understandingStats: return "chart.bar.fill"
        case .managingAthletes: return "person.fill"
        case .seasonTracking: return "calendar"
        case .gameManagement: return "sportscourt.fill"
        case .crossDeviceSync: return "arrow.triangle.2.circlepath"
        case .videoStorage: return "externaldrive.fill"
        case .exportingData: return "arrow.down.doc"
        case .deletingAccount: return "trash"
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
            • Formula: (Hits + Walks) ÷ (At-Bats + Walks)
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

            **What Doesn't Sync:**
            ❌ Actual video files (they stay on the device that recorded them)
            ❌ Video thumbnails

            **How It Works:**
            1. Sign in with the same account on multiple devices
            2. Data automatically syncs in the background every 60 seconds
            3. Changes appear on other devices within seconds
            4. Works offline—syncs when internet is available

            **Sync Status:**
            • Green checkmark = Synced
            • Spinning indicator = Syncing now
            • Warning icon = Sync failed (will retry)

            **Why Don't Videos Sync?**
            Video files are large (50-100MB each). Syncing them would:
            • Use significant mobile data
            • Consume cloud storage quota
            • Slow down sync

            Instead, only the metadata syncs (game info, tags, statistics). You can see what videos exist on other devices, but the actual video stays local.

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
            Video files are NOT uploaded to cloud storage by default. Only metadata (tags, dates, game info) syncs to the cloud.

            **Backing Up Videos:**
            To backup videos:
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
        }
    }
}

struct HelpArticleDetailView: View {
    let article: HelpArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: article.icon)
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .cornerRadius(12)

                    Text(article.title)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top)

                Divider()

                // Content
                Text(article.content)
                    .font(.body)
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
        HelpArticleDetailView(article: .recordingVideos)
    }
}
