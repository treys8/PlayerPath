//
//  BulkPhotoImportAttach.swift
//  PlayerPath
//
//  ViewModifier mirror of BulkImportAttach for photos. Attaches a PhotosPicker
//  → progress overlay → completion toast pipeline and routes every imported
//  photo to the caller-supplied season (falling back to matching the EXIF
//  capture date, then the athlete's active season). Call sites supply a trigger
//  binding — flipping it to true opens the library picker.
//
//  Shares `BulkImportOutcome` (and therefore its result copy, de-duplication and
//  storage-full handling) with the video pipeline so the two cannot drift.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Matches the video cap. See `maxImportSelection` in BulkImportAttach.
private let maxPhotoImportSelection = 100

struct BulkPhotoImportAttach: ViewModifier {
    let athlete: Athlete?
    var game: Game? = nil
    var practice: Practice? = nil
    var season: Season? = nil
    @Binding var trigger: Bool

    /// Singular, lowercase name of the event this import attaches to, or nil for a
    /// library-level import. Sport-aware: a golf `Game` is a "round".
    private var eventNoun: String? {
        if game != nil { return athlete?.sportType == .golf ? "round" : "game" }
        if practice != nil { return "practice" }
        return nil
    }

    @Environment(\.modelContext) private var modelContext

    @State private var showingPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var skippedSoFar = 0
    @State private var importTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @State private var toastKind: BulkImportToastKind = .success
    @State private var toastTask: Task<Void, Never>?

    // Post-import backfill prompt: photos whose EXIF capture date matched no
    // season (and fell back to the active season) on a non-pre-pinned import.
    @State private var unmatchedPhotos: [Photo] = []
    @State private var unmatchedEarliest: Date?
    @State private var unmatchedLatest: Date?
    @State private var showingBackfill = false

    /// Outcome parked until the backfill prompt is gone. Presenting the
    /// storage-full sheet over a live sibling sheet is silently dropped by
    /// SwiftUI and leaves this view unable to present anything again.
    @State private var pendingOutcome: BulkImportOutcome?
    @State private var storageContext: ImportStorageFullContext?
    @State private var pendingResume = false
    @State private var isResume = false

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPicker,
                selection: $pickerItems,
                maxSelectionCount: maxPhotoImportSelection,
                matching: .images
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                trigger = false
                guard athlete != nil else { return }
                // Don't open the picker while a post-import decision is in flight.
                guard pendingOutcome == nil, storageContext == nil else { return }
                isResume = false
                // See BulkImportAttach: ask for read access at the import entry
                // point so de-duplication is free and exact. Never gates the picker.
                Task { @MainActor in
                    await PhotosReadAccess.requestIfNeeded()
                    pickerItems = []
                    showingPicker = true
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty, let athlete else { return }
                let items = newItems
                pickerItems = []
                startImport(items, athlete: athlete)
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView(
                                value: Double(importProgress.current),
                                total: Double(max(importProgress.total, 1))
                            )
                            .tint(.white)
                            .frame(width: 160)

                            Text("Importing \(importProgress.current) of \(importProgress.total)")
                                .font(.bodyMedium)
                                .foregroundColor(.white)
                                .monospacedDigit()

                            // Recognizing a duplicate means loading the photo's
                            // bytes first, so a re-pick spends real time producing
                            // nothing. Naming the skips as they happen separates
                            // that from a stall.
                            if skippedSoFar > 0 {
                                Text("^[\(skippedSoFar) photo](inflect: true) already in your library")
                                    .font(.bodySmall)
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Button(role: .destructive) {
                                importTask?.cancel()
                            } label: {
                                Text("Cancel")
                                    .font(.headingSmall)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = toastMessage {
                    Text(message)
                        .font(.labelLarge)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(toastKind.color, in: Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingBackfill, onDismiss: backfillDismissed) {
                if let athlete {
                    BackfillSeasonPromptView(
                        athlete: athlete,
                        unmatchedCount: unmatchedPhotos.count,
                        dateRange: (unmatchedEarliest ?? Date())...(unmatchedLatest ?? Date()),
                        currentSeasonName: athlete.activeSeason?.displayName ?? "your current season",
                        onResolve: reroute
                    )
                }
            }
            .sheet(item: $storageContext, onDismiss: storageSheetDismissed) { ctx in
                ImportStorageFullSheet(context: ctx) { pendingResume = true }
            }
    }

    private func startImport(_ items: [PhotosPickerItem], athlete: Athlete) {
        importProgress = (0, items.count)
        skippedSoFar = 0
        isImporting = true
        importTask = Task { @MainActor in
            await importPhotos(items, athlete: athlete)
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem], athlete: Athlete) async {
        let service = PhotoPersistenceService()
        let allSeasons = athlete.seasons ?? []
        // Pre-pinned imports (a specific game/practice/season was supplied) never
        // prompt — the caller already chose the target.
        let prePinned = game != nil || practice != nil || season != nil
        var outcome = BulkImportOutcome()
        outcome.wasResume = isResume
        unmatchedPhotos = []
        unmatchedEarliest = nil
        unmatchedLatest = nil

        // Dedupe keys already claimed by this athlete's live photos, read once.
        // `insert(_:).inserted` also catches the same asset twice in one batch.
        var claimed = ImportDedupeKey.existingPhotoKeys(for: athlete)
        // Only fingerprint when some existing row actually needs it — rows written
        // before the app held Photos read access carry `cf:` keys.
        let mustCheckContentKeys = ImportDedupeKey.containsContentKeys(claimed)

        // One storage snapshot for the whole batch — it stats every un-uploaded
        // file in the library, so it must not run per item. Photos had NO quota
        // check at all before this; a backfill could fill the plan silently.
        let user = athlete.user
        var storage: ProjectedCloudStorage.Snapshot?
        if let user {
            storage = await ProjectedCloudStorage.snapshot(for: user)
        }
        var reserved: Int64 = 0

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            importProgress = (index + 1, items.count)

            // FIRST: the free check, before any bytes are loaded.
            let libraryKey = ImportDedupeKey.libraryKey(for: item)
            if let libraryKey, claimed.contains(libraryKey) {
                outcome.skippedDuplicates += 1
                skippedSoFar = outcome.skippedDuplicates
                continue
            }

            do {
                // The load gets its own catch: a PhotosPickerItem that went stale
                // across a StoreKit purchase THROWS rather than returning nil, and
                // routing that to `failed` would make `allLoadsFailed` — the whole
                // point of tracking load errors apart — permanently unreachable.
                let loaded: Data?
                do {
                    loaded = try await item.loadTransferable(type: Data.self)
                } catch is CancellationError {
                    break
                } catch {
                    loaded = nil
                }
                guard let data = loaded else {
                    outcome.loadFailures += 1
                    continue
                }

                // SECOND: the fingerprint, needed when there is no library key
                // (access declined) or when older rows still carry `cf:` keys.
                // Hash the SOURCE bytes — `savePhotoFromData` re-encodes to JPEG,
                // so a key derived from the stored file would never match a second
                // import of the same asset.
                var contentKey: String?
                if libraryKey == nil || mustCheckContentKeys {
                    contentKey = await Task.detached(priority: .userInitiated) {
                        ImportDedupeKey.contentKey(for: data)
                    }.value
                }
                let dedupeKey = libraryKey ?? contentKey

                // Test now, CLAIM after the save — claiming here would mark an
                // asset present even if its save threw, so a genuine retry later
                // in the batch would report "already in your library" with nothing
                // written.
                if let contentKey, claimed.contains(contentKey) {
                    outcome.skippedDuplicates += 1
                    skippedSoFar = outcome.skippedDuplicates
                    continue
                }

                // Pre-flight gate on the source bytes — the only size known
                // before the write. NOTE this UNDER-estimates: `savePhotoFromData`
                // re-encodes to a 4000px JPEG at quality 0.8, which for the default
                // iPhone HEIC is routinely ~2x the source. The running total is
                // corrected with the real file size after each save, so the error
                // does not compound across the batch.
                let sourceBytes = Int64(data.count)
                if let storage, !storage.fits(sourceBytes, alreadyReserved: reserved) {
                    outcome.stoppedForQuota = true
                    outcome.blockedItemBytes = sourceBytes
                    // Inclusive of the current item — it did not land.
                    outcome.remaining = Array(items[index...])
                    break
                }

                // Pull EXIF capture date first so we can route the photo to the
                // right season. A preset game/practice wins (the photo inherits
                // that event's season — mirrors BulkVideoImportViewModel); then
                // an explicit `season` prop; then match by capture date; then
                // activeSeason.
                let exifDate = service.extractCaptureDate(from: data)
                let resolvedSeason: Season?
                // Tracks the silent-misfile case: a non-pre-pinned photo whose
                // EXIF date matched no season and fell back to the active one.
                var dateUnmatched = false
                if let game {
                    resolvedSeason = game.season ?? athlete.activeSeason
                } else if let practice {
                    resolvedSeason = practice.season ?? athlete.activeSeason
                } else if let season {
                    resolvedSeason = season
                } else if let exifDate {
                    let dateMatch = Season.season(containing: exifDate, in: allSeasons)
                    resolvedSeason = dateMatch ?? athlete.activeSeason
                    // Only flag when genuinely OLDER than the current season (see
                    // BulkVideoImportViewModel): newer-than-any/future-dated photos
                    // stay on the active season.
                    if let start = athlete.activeSeason?.startDate {
                        dateUnmatched = (dateMatch == nil && exifDate < start)
                    }
                } else {
                    resolvedSeason = athlete.activeSeason
                }

                // Second-precision EXIF dates tie on sort for burst imports;
                // nudge by a microsecond per index so the list remains stable.
                let nudgedDate = exifDate?.addingTimeInterval(Double(index) / 1_000_000.0)

                let photo = try await service.savePhotoFromData(
                    data,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    practice: practice,
                    season: resolvedSeason,
                    captureDate: nudgedDate,
                    importSourceKey: dedupeKey
                )
                outcome.succeeded += 1
                if let dedupeKey { claimed.insert(dedupeKey) }
                // Account what was actually written, not what was handed to us.
                // `SyncCoordinator+Photos` measures this same file against the same
                // cap, so under-counting here commits photos that can never upload.
                reserved += FileManager.default.fileSize(atPath: photo.resolvedFilePath)

                if !prePinned, dateUnmatched, let exifDate {
                    unmatchedPhotos.append(photo)
                    unmatchedEarliest = min(unmatchedEarliest ?? exifDate, exifDate)
                    unmatchedLatest = max(unmatchedLatest ?? exifDate, exifDate)
                }
            } catch is CancellationError {
                // User cancelled mid-item: not a failure, and not worth reporting.
                break
            } catch {
                ErrorHandlerService.shared.handle(error, context: "BulkPhotoImportAttach.import", showAlert: false)
                outcome.failed += 1
            }
        }

        outcome.importedBytes = reserved
        outcome.wasCancelled = Task.isCancelled
        // No `resumeSeason`: the photo resume re-enters `importPhotos`, which reads
        // this modifier's own `season` prop. Only the video path, which rebuilds a
        // sheet, needs the season carried on the outcome.
        outcome.storageSnapshot = storage

        AnalyticsService.shared.trackPhotosBulkImported(
            count: outcome.succeeded,
            skippedDuplicates: outcome.skippedDuplicates,
            stoppedForQuota: outcome.stoppedForQuota,
            wasResume: outcome.wasResume,
            totalSizeBytes: outcome.importedBytes
        )

        isImporting = false
        importTask = nil

        // Offer to re-home photos filed on the current season only because their
        // capture dates matched no season, BEFORE acting on the outcome — the
        // storage decision happens once every other sheet is gone.
        if !unmatchedPhotos.isEmpty, athlete.activeSeason != nil {
            pendingOutcome = outcome
            showingBackfill = true
        } else {
            route(outcome, athlete: athlete)
        }
    }

    // MARK: - Post-import routing

    private func backfillDismissed() {
        guard let outcome = pendingOutcome, let athlete else { return }
        pendingOutcome = nil
        route(outcome, athlete: athlete)
    }

    private func route(_ outcome: BulkImportOutcome, athlete: Athlete) {
        // A resumed run whose every item failed to load means the picker
        // selection went stale while the user was buying — not that the photos
        // are broken. Say so and reopen the picker rather than reporting a wall
        // of failures at the moment they just paid.
        if outcome.wasResume && outcome.allLoadsFailed {
            showToast("Selection expired — pick them again", kind: .warning)
            isResume = false
            showingPicker = true
            return
        }

        if outcome.stoppedForQuota {
            // A live @Model that has since been wiped (sign-out) traps on access,
            // and this one is held in @State across a StoreKit purchase.
            guard let user = athlete.user, user.modelContext != nil else {
                showToast("Storage full — import stopped", kind: .warning)
                return
            }
            // Present synchronously from the snapshot the run already took —
            // awaiting a fresh one here leaves the screen live with no sheet up,
            // long enough for the user to reopen the picker and lose this sheet.
            storageContext = ImportStorageFullContext(
                outcome: outcome,
                user: user,
                snapshot: outcome.storageSnapshot ?? .empty,
                mediaNoun: "photo"
            )
            return
        }

        if let copy = outcome.toastCopy(mediaNoun: "photo", eventNoun: eventNoun) {
            showToast(copy.text, kind: copy.kind)
        }
    }

    /// Runs once the storage sheet is gone. Re-runs the remainder when a purchase
    /// landed. The resumed run re-snapshots storage and re-runs the identical
    /// `fits(...)` test, so it cannot be under-gated: if the purchased tier is
    /// still too small it stops and re-presents the sheet with updated counts,
    /// which terminates because each pass imports strictly more.
    private func storageSheetDismissed() {
        let ctx = storageContext
        storageContext = nil
        guard pendingResume,
              let remaining = ctx?.outcome.remaining, !remaining.isEmpty,
              let athlete else {
            pendingResume = false
            return
        }
        pendingResume = false
        isResume = true
        startImport(remaining, athlete: athlete)
    }

    /// Re-homes the date-unmatched photos to the chosen season (nil = keep on
    /// current). Marks them dirty and kicks off a background metadata sync.
    private func reroute(to season: Season?) {
        defer { unmatchedPhotos = [] }
        guard let season else { return }
        for photo in unmatchedPhotos {
            photo.season = season
            photo.needsSync = true
            photo.version += 1
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "BulkPhotoImport.reroute")
        if let user = athlete?.user {
            Task {
                do {
                    try await SyncCoordinator.shared.syncPhotos(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "BulkPhotoImport.syncPhotos", showAlert: false)
                }
            }
        }
    }

    private func showToast(_ message: String, kind: BulkImportToastKind) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4)) {
            toastMessage = message
            toastKind = kind
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { toastMessage = nil }
        }
    }
}

extension View {
    func bulkPhotoImportAttach(
        athlete: Athlete?,
        game: Game? = nil,
        practice: Practice? = nil,
        season: Season? = nil,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(BulkPhotoImportAttach(athlete: athlete, game: game, practice: practice, season: season, trigger: trigger))
    }
}
