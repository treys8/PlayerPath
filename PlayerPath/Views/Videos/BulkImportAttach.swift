//
//  BulkImportAttach.swift
//  PlayerPath
//
//  ViewModifier that attaches the bulk video-import UI (Photos picker → progress
//  sheet → completion toast, or the storage-full upgrade sheet) to any view.
//  Owns all presentation state so call sites only need a trigger binding +
//  athlete (and optional game/practice).
//

import SwiftUI
import SwiftData
import PhotosUI

/// 100, up from 20. A camera-roll backfill spanning two seasons was several
/// sittings at the old cap; de-duplication is what makes the overlapping
/// selections that implies harmless.
private let maxImportSelection = 100

struct BulkImportAttach: ViewModifier {
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

    @State private var showingPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingItems: [PhotosPickerItem] = []
    @State private var showingSheet = false
    @State private var toastMessage: String?
    @State private var toastKind: BulkImportToastKind = .success
    @State private var toastTask: Task<Void, Never>?

    // Resume/season state for a run that is finishing an interrupted batch.
    @State private var resumeSeason: Season?
    @State private var skipConfirmation = false
    @State private var isResume = false

    /// Outcome parked by the import sheet's `onComplete`, acted on in its
    /// `onDismiss`. Presenting the storage sheet over a live sibling sheet is
    /// silently dropped by SwiftUI and leaves the binding "presented", blocking
    /// every later sheet from this view — so the decision is always made after
    /// the import sheet is gone.
    @State private var pendingOutcome: BulkImportOutcome?
    @State private var storageContext: ImportStorageFullContext?
    /// Set by the storage sheet when a purchase lands; acted on in ITS onDismiss,
    /// for the same reason.
    @State private var pendingResume = false
    /// Set when a tap is refused by the `bulkVideoImport` kill switch.
    @State private var pausedMessage: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPicker,
                selection: $pickerItems,
                maxSelectionCount: maxImportSelection,
                matching: .videos,
                preferredItemEncoding: .compatible
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                trigger = false
                guard athlete != nil else { return }
                // Don't open the picker while a post-import decision is still
                // in flight — a picker presented over the pending storage sheet
                // would drop it silently and strand this view's presentation.
                guard pendingOutcome == nil, storageContext == nil else { return }
                // Remote kill switch (appConfig/killSwitches). Gates the action, not
                // the entry point: every Import button stays put and says why.
                if KillSwitchService.shared.isKilled(.bulkVideoImport) {
                    pausedMessage = KillSwitchService.shared.message(for: .bulkVideoImport)
                    return
                }
                // A fresh pick is never a resume.
                resumeSeason = nil
                skipConfirmation = false
                isResume = false
                // Ask for Photos read access once, here, where the user has just
                // asked to bring in library media. Grants make de-duplication free
                // and exact; a decline changes nothing but the cost. Never gates
                // the picker, which is out-of-process and needs no authorization.
                Task { @MainActor in
                    await PhotosReadAccess.requestIfNeeded()
                    pickerItems = []
                    showingPicker = true
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                pendingItems = newItems
                pickerItems = []
                showingSheet = true
            }
            .sheet(isPresented: $showingSheet, onDismiss: importSheetDismissed) {
                if let athlete = athlete {
                    BulkVideoImportSheet(
                        items: pendingItems,
                        athlete: athlete,
                        game: game,
                        practice: practice,
                        preselectedSeason: resumeSeason ?? season,
                        skipConfirmation: skipConfirmation,
                        isResume: isResume
                    ) { outcome in
                        pendingOutcome = outcome
                    }
                    // The confirmation Form carries a season picker; .medium clips it.
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(item: $storageContext, onDismiss: storageSheetDismissed) { ctx in
                ImportStorageFullSheet(context: ctx) { pendingResume = true }
            }
            .alert(
                "Import Paused",
                isPresented: Binding(
                    get: { pausedMessage != nil },
                    set: { if !$0 { pausedMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pausedMessage ?? "")
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
    }

    // MARK: - Post-import routing

    /// Runs once the import sheet is fully gone, so anything presented here can
    /// actually appear.
    private func importSheetDismissed() {
        guard let outcome = pendingOutcome else { return }
        pendingOutcome = nil
        pendingItems = []

        // A resumed run whose every item failed to load means the picker
        // selection went stale while the user was buying — not that 37 videos
        // are broken. Say so and reopen the picker rather than reporting a wall
        // of failures at the moment they just paid.
        if outcome.wasResume && outcome.allLoadsFailed {
            showToast("Selection expired — pick them again", kind: .warning)
            resumeSeason = nil
            skipConfirmation = false
            isResume = false
            showingPicker = true
            return
        }

        if outcome.stoppedForQuota {
            guard let user = athlete?.user else {
                // Unreachable — without a user there is no storage gate to trip —
                // but never leave the stop silent if it ever becomes reachable.
                showToast("Storage full — import stopped", kind: .warning)
                return
            }
            // Stamp the resume state NOW, before any await: `outcome.resumeSeason`
            // is a @Model, and this module's convention is to read models out
            // before suspending rather than after.
            // A live @Model that has since been wiped (sign-out) traps on access,
            // and this one is held in @State across a StoreKit purchase.
            guard user.modelContext != nil else {
                showToast("Storage full — import stopped", kind: .warning)
                return
            }
            resumeSeason = outcome.resumeSeason
            skipConfirmation = outcome.seasonWasConfirmed
            // Present synchronously from the snapshot the run already took. Taking
            // a fresh one here would mean an await with the screen live and no
            // sheet up — long enough for the user to open the picker again, and the
            // storage sheet would then be presented over it and lost for good.
            storageContext = ImportStorageFullContext(
                outcome: outcome,
                user: user,
                snapshot: outcome.storageSnapshot ?? .empty,
                mediaNoun: "video"
            )
            return
        }

        if let copy = outcome.toastCopy(mediaNoun: "video", eventNoun: eventNoun) {
            showToast(copy.text, kind: copy.kind)
        }
    }

    /// Runs once the storage sheet is gone. Re-presents the import sheet with the
    /// remainder when a purchase landed.
    private func storageSheetDismissed() {
        let ctx = storageContext
        storageContext = nil
        guard pendingResume, let remaining = ctx?.outcome.remaining, !remaining.isEmpty else {
            pendingResume = false
            return
        }
        pendingResume = false
        pendingItems = remaining
        isResume = true
        // resumeSeason / skipConfirmation were stamped before presenting.
        // The resumed run re-snapshots storage at the top of runImport and
        // re-runs the identical `fits(...)` test, so it cannot be under-gated:
        // if the purchased tier is still too small it stops and re-presents this
        // sheet with updated counts, which terminates because each pass imports
        // strictly more.
        showingSheet = true
    }

    private func showToast(_ message: String, kind: BulkImportToastKind) {
        // Cancel any previous dismissal so a stale timer can't clear this toast.
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4)) {
            toastMessage = message
            toastKind = kind
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) {
                toastMessage = nil
            }
        }
    }

}

extension View {
    func bulkImportAttach(
        athlete: Athlete?,
        game: Game? = nil,
        practice: Practice? = nil,
        season: Season? = nil,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(BulkImportAttach(athlete: athlete, game: game, practice: practice, season: season, trigger: trigger))
    }
}
