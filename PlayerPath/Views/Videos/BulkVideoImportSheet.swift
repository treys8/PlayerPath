//
//  BulkVideoImportSheet.swift
//  PlayerPath
//
//  Modal progress UI for bulk-importing videos from the Photos library.
//  Owns a BulkVideoImportViewModel and dismisses on completion via the
//  onComplete callback so the parent can surface a result toast.
//

import SwiftUI
import SwiftData
import PhotosUI

struct BulkVideoImportSheet: View {
    let items: [PhotosPickerItem]
    let athlete: Athlete
    var game: Game? = nil
    var practice: Practice? = nil
    /// When set by the caller (e.g., an upload button inside a specific
    /// season's detail view), the user has already chosen the target season
    /// so confirmation is skipped and every clip is routed to this season.
    var preselectedSeason: Season? = nil
    /// Set when the season question is already settled — notably on a run resumed
    /// after a storage upgrade. Deliberately NOT folded into `preselectedSeason`:
    /// a user who chose "Match by date" made a real decision whose season is
    /// legitimately nil, and overloading the season prop would re-ask them.
    var skipConfirmation: Bool = false
    /// This sheet is finishing the remainder of an earlier interrupted run.
    var isResume: Bool = false
    let onComplete: (BulkImportOutcome) -> Void

    @State private var viewModel = BulkVideoImportViewModel()
    @State private var hasStarted = false
    @State private var seasonOverride: Season?
    @State private var showingBackfill = false
    @State private var pendingCompletion: BulkImportOutcome?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    /// Confirmation appears only when the user has multiple seasons AND the
    /// parent didn't pre-pin a game/practice/season. In every other case,
    /// import starts instantly (legacy behavior).
    private var shouldConfirm: Bool {
        !skipConfirmation &&
        preselectedSeason == nil &&
        game == nil && practice == nil &&
        (athlete.seasons?.count ?? 0) > 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasStarted && shouldConfirm {
                    confirmationView
                } else {
                    importingView
                }
            }
            .interactiveDismissDisabled()
            .task {
                guard !shouldConfirm else { return }
                await startImport()
            }
            .sheet(isPresented: $showingBackfill, onDismiss: finishAfterBackfill) {
                BackfillSeasonPromptView(
                    athlete: athlete,
                    unmatchedCount: viewModel.unmatchedClips.count,
                    dateRange: (viewModel.unmatchedEarliest ?? Date())...(viewModel.unmatchedLatest ?? Date()),
                    currentSeasonName: athlete.activeSeason?.displayName ?? "your current season",
                    onResolve: reroute
                )
            }
        }
    }

    private var confirmationView: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.title2)
                        .foregroundStyle(ppAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Import")
                            .font(.headingLarge)
                        Text("^[\(items.count) video](inflect: true) selected")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                SeasonPickerRow(
                    athlete: athlete,
                    selection: $seasonOverride,
                    allowsNone: true,
                    noneLabel: "Match by date (recommended)"
                )
            } header: {
                Text("Season").smallCapsLabel()
            } footer: {
                if seasonOverride == nil {
                    Text("Each video is placed on the season that contains its capture date. Pick a specific season to override.")
                } else {
                    Text("All imported videos will be placed on this season, regardless of capture date.")
                }
            }

            Section {
                Button {
                    Task { await startImport() }
                } label: {
                    Text("Start Import")
                        .font(.headingMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ppAccent)

                Button(role: .cancel) {
                    onComplete(BulkImportOutcome(wasCancelled: true))
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .ppDetailBackground()
        .navigationTitle("Import Videos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var importingView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(ppAccent)

            Text("Importing Videos")
                .font(.displayMedium)

            if case .importing(let current, let total) = viewModel.status {
                VStack(spacing: 12) {
                    ProgressView(value: Double(current), total: Double(total))
                        .tint(ppAccent)
                        .padding(.horizontal, 40)
                    Text("\(current) of \(total)")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    // Recognizing a duplicate requires exporting the video from
                    // the Photos library first, so a re-pick spends real time
                    // producing nothing. Naming the skips as they happen is what
                    // separates that from a stall.
                    if viewModel.skippedSoFar > 0 {
                        Text("^[\(viewModel.skippedSoFar) video](inflect: true) already in your library")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if case .importing = viewModel.status {
                if viewModel.isCancelled {
                    // Cancellation is only checked between items, and a large
                    // `loadTransferable` cannot be interrupted — so say so rather
                    // than leaving a dead Cancel button on screen.
                    Text("Finishing current video…")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 32)
                } else {
                    Button(role: .destructive) {
                        viewModel.cancel()
                    } label: {
                        Text("Cancel")
                            .font(.headingMedium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func startImport() async {
        hasStarted = true
        let chosenSeason = seasonOverride ?? preselectedSeason
        await viewModel.runImport(
            items: items,
            athlete: athlete,
            modelContext: modelContext,
            game: game,
            practice: practice,
            seasonOverride: chosenSeason,
            wasResume: isResume
        )
        if case .completed(var outcome) = viewModel.status {
            // Carry the season decision forward so a run resumed after a storage
            // upgrade files the remainder identically. By the time we reach here
            // the question is always settled — either the user confirmed, or
            // there was nothing to ask — so a resumed sheet must never re-ask.
            outcome.resumeSeason = chosenSeason
            outcome.seasonWasConfirmed = true

            // If any clips were filed on the current season only because their
            // capture dates matched no season, offer to re-home them before
            // finishing. The outcome is parked and handed out on dismiss so the
            // caller's storage-full decision happens after this sheet is gone.
            if !viewModel.unmatchedClips.isEmpty, athlete.activeSeason != nil {
                pendingCompletion = outcome
                showingBackfill = true
            } else {
                onComplete(outcome)
                dismiss()
            }
        }
    }

    /// Re-homes the date-unmatched clips to the chosen season (nil = keep on
    /// current). Marks them dirty and kicks off a background metadata sync.
    private func reroute(to season: Season?) {
        guard let season else { return }
        for clip in viewModel.unmatchedClips {
            clip.season = season
            clip.seasonName = season.displayName
            clip.needsSync = true
            clip.version += 1
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "BulkVideoImport.reroute")
        if let user = athlete.user {
            Task {
                do {
                    try await SyncCoordinator.shared.syncVideos(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "BulkVideoImport.syncVideos", showAlert: false)
                }
            }
        }
    }

    /// Fires once the backfill prompt is dismissed (after the user resolved it),
    /// completing the import and closing the sheet.
    private func finishAfterBackfill() {
        onComplete(pendingCompletion ?? BulkImportOutcome())
        dismiss()
    }
}
