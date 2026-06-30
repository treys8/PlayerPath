//
//  GameDetailView.swift
//  PlayerPath
//
//  Detail view for a single game showing stats, clips, and actions.
//

import SwiftUI
import SwiftData

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingEndGame = false
    @State private var showingVideoRecorder = false
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
    @State private var showingPitchingStats = false
    @State private var showingEditGame = false
    @State private var showingPhotoCamera = false
    @State private var showingScoreEntry = false
    /// Presents the full-round scorecard grid (all holes on one screen).
    @State private var showingScorecard = false
    @State private var showingScanScorecard = false
    @State private var gameService: GameService? = nil
    /// Hole picked for per-hole scoring; non-nil presents ScoreHoleSheet.
    /// Use a wrapper instead of a bare Int so `.sheet(item:)` redraws when
    /// the user opens different holes back-to-back.
    @State private var scoreHoleTarget: ScoreHoleTarget? = nil
    /// Reel export (Plus+): generate a shareable highlight reel from this game's
    /// starred clips. Free taps route to the paywall instead.
    @State private var showingReel = false
    @State private var showingReelPaywall = false

    private var isGolf: Bool { game.season?.sport == .golf }
    // A single golf game is a "Round" — "Tournament" now means the multi-round
    // GolfTournament container (SchemaV27).
    private var unitNoun: String { isGolf ? "Round" : "Game" }
    private var unitNounLower: String { isGolf ? "round" : "game" }

    // Bulk import from Photos — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false
    // Bulk PHOTO import preset to this game — owned by BulkPhotoImportAttach.
    @State private var photoImportTrigger = false

    var videoClips: [VideoClip] {
        (game.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Starred clips for this game in chronological (playback) order.
    private var reelClips: [VideoClip] {
        (game.videoClips ?? [])
            .filter { $0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// A reel needs at least two clips — one clip is just a clip.
    private var reelEligible: Bool { reelClips.count >= 2 }

    private var reelTitle: String {
        guard let date = game.date else { return game.opponent }
        return "\(game.opponent) · \(DateFormatter.mediumDate.string(from: date))"
    }

    /// Plus-gated: open the generator, or route free users to the paywall.
    private func generateReelTapped() {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            showingReel = true
        } else {
            showingReelPaywall = true
        }
    }

    var gamePhotos: [Photo] {
        (game.photos ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Per-hole rows for this game, ascending by hole. Empty when none entered.
    private var holeScores: [HoleScore] {
        (game.holeScores ?? []).sorted { $0.holeNumber < $1.holeNumber }
    }

    /// Hole numbers (ascending) that have at least one clip — drives the golf
    /// "by hole" clip navigation. A scored hole with no clips needs no review
    /// row, so this keys off clips, not scores.
    private var clipHoleNumbers: [Int] {
        Set(videoClips.compactMap { $0.holeNumber }).sorted()
    }

    /// Clips with no hole stamped (recorded before scoring, or imported). They
    /// get an "Unassigned" bucket so they stay reachable for review/retagging.
    private var unassignedClipCount: Int {
        videoClips.filter { $0.holeNumber == nil }.count
    }

    private func clipCount(onHole hole: Int) -> Int {
        videoClips.filter { $0.holeNumber == hole }.count
    }

    private func holeScore(_ hole: Int) -> HoleScore? {
        holeScores.first { $0.holeNumber == hole }
    }

    /// First unscored hole in 1…holes, or nil once every hole is scored. Drives
    /// the live "Score Hole X" CTA, which is hidden when this is nil so a
    /// finished round can't gain a 19th hole. Returns the first *gap* (not
    /// max+1) so a skipped middle hole is offered before the round is done.
    private var nextHoleNumber: Int? {
        let total = game.holes ?? 18
        let scored = Set(holeScores.map(\.holeNumber))
        return (1...total).first { !scored.contains($0) }
    }

    /// Current per-hole par/yardage, so a re-scan pre-fills cells the new scan
    /// didn't read instead of blanking them. Keyed by hole number.
    private var existingScannedByHole: [Int: (par: Int?, yardage: Int?)] {
        var result: [Int: (par: Int?, yardage: Int?)] = [:]
        for hole in (game.holeScores ?? []) {
            let entry: (par: Int?, yardage: Int?) = (hole.par, hole.yardage)
            result[hole.holeNumber] = entry
        }
        return result
    }

    var body: some View {
        List {
            // Game Info Section
            Section(header: Text(isGolf ? "Round Details" : "Game Details").smallCapsLabel()) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(isGolf ? "Course" : "Opponent")
                            .font(.headingMedium)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date")
                            .font(.headingMedium)
                        Spacer()
                        if let date = game.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let location = game.location, !location.isEmpty {
                        HStack {
                            Text("Location")
                                .font(.headingMedium)
                            Spacer()
                            Text(location)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Status")
                            .font(.headingMedium)
                        Spacer()

                        Group {
                            switch game.displayStatus {
                            case .live:
                                Text("LIVE")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            case .completed:
                                // Past-dated games that were never started/ended show
                                // as PAST so the user can tell stats won't count until
                                // they tap Mark Complete.
                                Text(game.isComplete ? "COMPLETED" : "PAST")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            case .scheduled:
                                Text("SCHEDULED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandNavy)
                                    .cornerRadius(4)
                            }
                        }
                        .font(.custom("Inter18pt-Bold", size: 12, relativeTo: .caption))
                    }

                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.headingMedium)
                            Text(notes)
                                .foregroundColor(.secondary)
                                .font(.bodyMedium)
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            // Score Section (golf only)
            if isGolf {
                Section(header: Text("Score").smallCapsLabel()) {
                    if let score = game.effectiveTotalScore {
                        // Hero readout: score + colored to-par anchored left, a
                        // compact secondary stat (holes played mid-round, or par
                        // once the round is complete) anchored right so the row
                        // uses the full width instead of trailing into dead space.
                        let total = game.holes ?? 18
                        let scored = holeScores.count
                        let inProgress = scored > 0 && scored < total
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(score)")
                                    .font(.ppStatLarge)
                                    .monospacedDigit()
                                    .foregroundColor(.primary)
                                if let par = game.effectivePar {
                                    let diff = score - par
                                    Text(diff == 0 ? "Even par"
                                         : (diff > 0 ? "\(diff) over par" : "\(-diff) under par"))
                                        .font(.headingSmall)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.parRelative(diff))
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if inProgress {
                                    Text("\(scored)/\(total)")
                                        .font(.headingMedium)
                                        .monospacedDigit()
                                    Text("THRU")
                                        .font(.labelSmall)
                                        .foregroundColor(.secondary)
                                } else if let par = game.effectivePar {
                                    Text("\(par)")
                                        .font(.headingMedium)
                                        .monospacedDigit()
                                    Text("PAR")
                                        .font(.labelSmall)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(total)")
                                        .font(.headingMedium)
                                        .monospacedDigit()
                                    Text("HOLES")
                                        .font(.labelSmall)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    } else {
                        Button(action: { showingScoreEntry = true }) {
                            Label("Enter Score", systemImage: "pencil.line")
                        }
                        .labelStyle(ActionRowLabelStyle())
                        .padding(.vertical, 5)
                    }

                    // Score the whole round on one screen (per-hole). The
                    // quick-total path stays available via "Enter Score" above.
                    Button(action: { showingScorecard = true }) {
                        Label("Scorecard", systemImage: "tablecells")
                    }
                    .labelStyle(ActionRowLabelStyle())
                }

                // Per-hole grid — read-only summary that's also tappable to edit
                // any prior hole. Only renders once at least one hole is scored.
                if !holeScores.isEmpty {
                    Section(header: Text("Holes").smallCapsLabel()) {
                        HoleScoreGrid(
                            holes: holeScores,
                            onTap: { hole in
                                scoreHoleTarget = ScoreHoleTarget(holeNumber: hole.holeNumber)
                            }
                        )
                        .padding(.vertical, 4)
                    }
                }
            }

            // Live/scheduled games are act-first: surface the contextual CTAs
            // (Record / Start / Score Hole) right under the details so the
            // primary action is reachable without scrolling past content.
            // Completed games are watch-first — their CTA block sits at the
            // bottom instead (see below). All editorial/destructive actions
            // live only in the `•••` toolbar menu either way.
            if game.displayStatus != .completed {
                contextualActions
            }

            // Video Clips Section
            Section(header: Text("Video Clips (\(videoClips.count))").smallCapsLabel()) {
                if videoClips.isEmpty {
                    // Empty state carries the affordance — a completed game can
                    // only gain clips by upload, a live/scheduled one by record.
                    if game.displayStatus == .completed {
                        Button(action: { importTrigger = true }) {
                            Label("Upload your first video", systemImage: "square.and.arrow.down.on.square")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    } else {
                        Button(action: { showingVideoRecorder = true }) {
                            Label("Record your first video", systemImage: "video.badge.plus")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                } else {
                    if reelEligible {
                        Button(action: { generateReelTapped() }) {
                            Label("Generate Highlight Reel", systemImage: "film.stack")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                    if isGolf {
                        // Golf rounds group clips by hole — a "film every swing"
                        // round can carry 50+ clips, unbrowsable as a flat list.
                        // Each row pushes that hole's clips + score + reel.
                        ForEach(clipHoleNumbers, id: \.self) { hole in
                            holeClipNavRow(holeNumber: hole, count: clipCount(onHole: hole))
                        }
                        if unassignedClipCount > 0 {
                            holeClipNavRow(holeNumber: nil, count: unassignedClipCount)
                        }
                    } else {
                        ForEach(videoClips) { clip in
                            VideoClipRow(clip: clip)
                        }
                    }
                }
            }

            // Photos Section
            Section(header: Text("Photos (\(gamePhotos.count))").smallCapsLabel()) {
                if gamePhotos.isEmpty {
                    addPhotoMenu
                        .labelStyle(ActionRowLabelStyle())
                } else {
                    ForEach(gamePhotos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo) {
                                deleteGamePhoto(photo)
                            }
                        } label: {
                            EventPhotoRow(photo: photo)
                        }
                    }
                }
            }

            // Game Statistics — hidden for golf (scoring lives in the Score section above)
            if !isGolf, let stats = game.gameStats {
                Section(header: Text("Game Statistics").smallCapsLabel()) {
                    HStack {
                        Text("At Bats")
                        Spacer()
                        Text("\(stats.atBats)")
                            .font(.headingMedium)
                    }
                    HStack {
                        Text("Hits")
                        Spacer()
                        Text("\(stats.hits)")
                            .font(.headingMedium)
                    }
                    // Runs and RBIs omitted — derivable-stats-only (no game context).
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.strikeouts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Ground Outs")
                        Spacer()
                        Text("\(stats.groundOuts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Fly Outs")
                        Spacer()
                        Text("\(stats.flyOuts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.walks)")
                            .font(.headingMedium)
                    }

                    // Calculate and show batting average for this game
                    if stats.atBats > 0 {
                        HStack {
                            Text("Batting Average")
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .font(.headingMedium)
                                .foregroundColor(.brandNavy)
                        }
                    }
                }
            }

            // Per-game pitching line — shown only when this game has pitching data.
            if !isGolf, let stats = game.gameStats, stats.hasPitchingData {
                Section(header: Text("Pitching").smallCapsLabel()) {
                    HStack {
                        Text("Innings Pitched")
                        Spacer()
                        Text(stats.inningsPitchedDisplay)
                            .font(.headingMedium)
                            .foregroundColor(.green)
                    }
                    if stats.outsRecorded > 0 {
                        HStack {
                            Text("ERA")
                            Spacer()
                            Text(String(format: "%.2f", stats.era))
                                .font(.headingMedium)
                                .foregroundColor(.red)
                        }
                        HStack {
                            Text("WHIP")
                            Spacer()
                            Text(String(format: "%.2f", stats.whip))
                                .font(.headingMedium)
                                .foregroundColor(Theme.warning)
                        }
                    }
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.pitchingStrikeouts)")
                            .font(.headingMedium)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.pitchingWalks)")
                            .font(.headingMedium)
                            .foregroundColor(.cyan)
                    }
                    HStack {
                        Text("Hits Allowed")
                        Spacer()
                        Text("\(stats.hitsAllowed)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Earned Runs")
                        Spacer()
                        Text("\(stats.earnedRuns)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                }
            }

            // Completed games are watch-first: the content greets you and the
            // additive CTAs (Upload / Add Photos) sit at the bottom as the floor.
            if game.displayStatus == .completed {
                contextualActions
            }
        }
        .ppDetailBackground()
        .navigationTitle("\(isGolf ? "at" : "vs") \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { primaryActionMenu }
        .alert(isGolf ? "End Round" : "End Game", isPresented: $showingEndGame) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Haptics.heavy()
                endGame()
            }
        } message: {
            Text("Are you sure you want to end this \(unitNounLower)? You won't be able to record more videos for it.")
        }
        .alert(isGolf ? "Delete Round" : "Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                deleteGame()
            }
        } message: {
            if game.isComplete, !videoClips.isEmpty || game.gameStats != nil {
                let clipCount = videoClips.count
                let hasStats = !isGolf && game.gameStats != nil
                if clipCount > 0 && hasStats {
                    Text("This \(unitNounLower) has \(clipCount) video clip\(clipCount == 1 ? "" : "s") and recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                } else if clipCount > 0 {
                    Text("This \(unitNounLower) has \(clipCount) video clip\(clipCount == 1 ? "" : "s"). Deleting it will permanently remove all data.")
                } else {
                    Text("This \(unitNounLower) has recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                }
            } else {
                Text("Are you sure you want to delete this \(unitNounLower)? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showingScoreEntry) {
            EnterScoreSheet(game: game)
        }
        .sheet(item: $scoreHoleTarget) { target in
            // One unified sheet: a Quick | Shot-by-shot switch picks the entry
            // style per hole. A hole that already has shots opens locked to
            // shot-by-shot, preserving the two-writer guard.
            HoleScoringSheet(game: game, holeNumber: target.holeNumber)
        }
        .sheet(isPresented: $showingScorecard) {
            GolfScorecardView(round: .game(game))
        }
        .fullScreenCover(isPresented: $showingScanScorecard) {
            if let athlete = game.athlete {
                ScorecardScanFlow(
                    athlete: athlete,
                    game: game,
                    holeCount: game.holes ?? 18,
                    existingByHole: existingScannedByHole,
                    onComplete: { holes, tee in
                        // Detail screen: the round exists, so write immediately.
                        GolfScoreWriter.applyScannedCard(holes, tee: tee, to: .game(game), context: modelContext)
                        ErrorHandlerService.shared.saveContext(modelContext, caller: "GameDetailView.scanScorecard")
                        showingScanScorecard = false
                    },
                    onCancel: { showingScanScorecard = false }
                )
            }
        }
        .fullScreenCover(isPresented: $showingVideoRecorder) {
            DirectCameraRecorderView(athlete: game.athlete, game: game)
        }
        .bulkImportAttach(athlete: game.athlete, game: game, trigger: $importTrigger)
        .bulkPhotoImportAttach(athlete: game.athlete, game: game, trigger: $photoImportTrigger)
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
        .sheet(isPresented: $showingPitchingStats) {
            ManualPitchingEntryView(game: game)
        }
        .sheet(isPresented: $showingEditGame) {
            EditGameSheet(game: game)
        }
        .fullScreenCover(isPresented: $showingPhotoCamera) {
            PhotoCameraView(
                onPhotoCaptured: { image in
                    saveGamePhoto(image)
                    showingPhotoCamera = false
                },
                onCancel: { showingPhotoCamera = false }
            )
        }
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(
                clips: reelClips,
                scopeKey: "game_\(game.id.uuidString)",
                title: reelTitle
            )
        }
        .sheet(isPresented: $showingReelPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
        .onAppear {
            if gameService == nil { gameService = GameService(modelContext: modelContext) }
        }
    }

    @ToolbarContentBuilder
    private var primaryActionMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                switch game.displayStatus {
                case .scheduled:
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(action: { startGame() }) {
                        Label(isGolf ? "Start Round" : "Start Game", systemImage: "play.circle")
                    }
                case .live:
                    if isGolf, let next = nextHoleNumber {
                        Button(action: {
                            scoreHoleTarget = ScoreHoleTarget(holeNumber: next)
                        }) {
                            Label("Score Hole \(next)", systemImage: "flag.checkered")
                        }
                    }
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(action: { Haptics.warning(); showingEndGame = true }) {
                        Label(isGolf ? "End Round" : "End Game", systemImage: "stop.circle")
                    }
                case .completed:
                    Button(action: { importTrigger = true }) {
                        Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                    }
                    if !game.isComplete {
                        Button(action: { completeGame() }) {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                    }
                }

                addPhotoMenu

                if reelEligible {
                    Button(action: { generateReelTapped() }) {
                        Label("Generate Highlight Reel", systemImage: "film.stack")
                    }
                }

                Divider()

                if !isGolf {
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Batting Stats", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button(action: { showingPitchingStats = true }) {
                        Label("Enter Pitching Stats", systemImage: "figure.baseball")
                    }
                } else {
                    Button(action: { showingScorecard = true }) {
                        Label("Scorecard", systemImage: "tablecells")
                    }
                    Button(action: { showingScanScorecard = true }) {
                        Label("Scan Scorecard", systemImage: "doc.viewfinder")
                    }
                    Button(action: { showingScoreEntry = true }) {
                        Label(game.effectiveTotalScore == nil ? "Enter Score" : "Edit Score", systemImage: "pencil.line")
                    }
                }

                Button(action: { showingEditGame = true }) {
                    Label(isGolf ? "Edit Round" : "Edit Game", systemImage: "pencil")
                }

                if game.isComplete {
                    Divider()
                    Button(action: { restartGame() }) {
                        Label(isGolf ? "Restart Round" : "Restart Game", systemImage: "arrow.counterclockwise")
                    }
                }

                if !game.isLive {
                    if !game.isComplete { Divider() }
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(isGolf ? "Delete Round" : "Delete Game", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
    }

    /// The slimmed in-body action block: only the additive / time-sensitive
    /// actions that belong on a viewer-first page. Everything editorial or
    /// destructive (Edit, Restart, Delete, End, Enter Statistics) lives solely
    /// in `primaryActionMenu` (the `•••` toolbar menu), which already mirrors
    /// the full set. Placed under details for live/scheduled, at the bottom for
    /// completed games (see `body`).
    @ViewBuilder
    private var contextualActions: some View {
        Section {
            switch game.displayStatus {
            case .scheduled:
                Button(action: { showingVideoRecorder = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                }
                Button(action: { startGame() }) {
                    Label(isGolf ? "Start Round" : "Start Game", systemImage: "play.circle")
                }
            case .live:
                // Score Hole is promoted above Record Video for golf live
                // rounds — entering a score is the primary action on each hole,
                // and clip attribution depends on it.
                if isGolf, let next = nextHoleNumber {
                    Button(action: {
                        scoreHoleTarget = ScoreHoleTarget(holeNumber: next)
                    }) {
                        Label("Score Hole \(next)", systemImage: "flag.checkered")
                    }
                }
                Button(action: { showingVideoRecorder = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                }
            case .completed:
                Button(action: { importTrigger = true }) {
                    Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                }
                if !game.isComplete {
                    Button(action: { completeGame() }) {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                    }
                }
            }

            // Add Photos is additive content on every status.
            addPhotoMenu
        }
        .labelStyle(ActionRowLabelStyle())
    }

    private var addPhotoMenu: some View {
        Menu {
            if PhotoCameraAvailability.isCameraAvailable {
                Button(action: { showingPhotoCamera = true }) {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button(action: { photoImportTrigger = true }) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
            }
        } label: {
            Label("Add Photos", systemImage: "camera")
        }
    }

    /// One row in the golf "by hole" clip list. Pushes HoleDetailView for the
    /// hole (or the Unassigned bucket when `holeNumber` is nil), showing the
    /// hole's score chip and clip count inline.
    @ViewBuilder
    private func holeClipNavRow(holeNumber: Int?, count: Int) -> some View {
        NavigationLink {
            HoleDetailView(round: .game(game), holeNumber: holeNumber)
        } label: {
            HStack(spacing: 8) {
                if let holeNumber {
                    Text("Hole \(holeNumber)")
                        .font(.headingMedium)
                    if let score = holeScore(holeNumber) {
                        Text(score.diffLabel)
                            .font(.labelSmall)
                            .foregroundColor(.parRelative(score.diff))
                    }
                } else {
                    Text("Unassigned")
                        .font(.headingMedium)
                }
                Spacer()
                Text("\(count) clip\(count == 1 ? "" : "s")")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func startGame() {
        Task { await gameService?.start(game) }
    }

    @MainActor
    private func endGame() {
        Task { await gameService?.end(game) }
    }

    @MainActor
    private func restartGame() {
        Task { await gameService?.restart(game) }
    }

    @MainActor
    private func completeGame() {
        Task { await gameService?.complete(game) }
    }

    @MainActor
    private func deleteGame() {
        Task {
            await gameService?.deleteGameDeep(game)
            dismiss()
        }
    }

    private func saveGamePhoto(_ image: UIImage) {
        guard let athlete = game.athlete else { return }
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    // Inherit the game's actual season, not just activeSeason —
                    // otherwise a photo on a past-season game mis-tags to the
                    // active season (matches the bulk-import path).
                    season: game.season ?? athlete.activeSeason
                )
                Haptics.success()
            } catch {
                ErrorHandlerService.shared.handle(error, context: "GameDetail.savePhoto", showAlert: false)
            }
        }
    }

    private func deleteGamePhoto(_ photo: Photo) {
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }
}
