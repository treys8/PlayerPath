//
//  ScorecardScanFlow.swift
//  PlayerPath
//
//  The end-to-end scorecard-scan orchestration (SchemaV32, Phase 2), shared by
//  both entry points (GameCreationView, GameDetailView) so the capture → OCR →
//  confirm sequence lives in one place. Present it as a `fullScreenCover`; it
//  walks: VisionKit capture → on-device OCR (offline) → the MANDATORY confirm
//  grid → `onComplete([ScannedHole], tee)`. The caller decides persistence
//  (write now on the detail screen, or stash until Save during creation).
//
//  The captured image is OCR'd directly (independent of photo persistence) and
//  also saved through the existing Photo pipeline (record + cloud upload),
//  flagged `isScorecardPhoto`.
//

import SwiftUI
import SwiftData

struct ScorecardScanFlow: View {
    let athlete: Athlete
    /// Set on the detail screen (photo attaches to the round, existing holes
    /// pre-fill); nil during creation (round doesn't exist yet).
    var game: Game? = nil
    var practice: Practice? = nil
    let holeCount: Int
    let existingByHole: [Int: (par: Int?, yardage: Int?)]
    let onComplete: ([GolfScoreWriter.ScannedHole], String?) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @State private var phase: Phase = .scanning

    private enum Phase {
        case scanning
        case processing
        case confirming(ScorecardExtraction)
    }

    var body: some View {
        switch phase {
        case .scanning:
            ScorecardScannerView(
                onScan: handleScan,
                onCancel: onCancel
            )
            .ignoresSafeArea()
        case .processing:
            VStack(spacing: 16) {
                ProgressView()
                Text("Reading scorecard…")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ppDetailBackground()
        case .confirming(let extraction):
            ScorecardConfirmGrid(
                extraction: extraction,
                holeCount: holeCount,
                existingByHole: existingByHole,
                onCancel: onCancel,
                onApply: onComplete
            )
        }
    }

    private func handleScan(_ image: UIImage) {
        phase = .processing
        Task {
            // Persist FIRST, before the long OCR await: the photo step reads the
            // round's relationships (old card, season), and doing that promptly
            // after capture — with no intervening await — avoids the
            // access-after-await trap if a concurrent sync deletes the round.
            await persistScorecardPhoto(image)
            // OCR off the captured image — works fully offline; a photo-save
            // failure above never blocks pre-fill.
            let extraction = await ScorecardOCR.extract(from: image)
            phase = .confirming(extraction)
        }
    }

    /// Best-effort: saves the card through the existing Photo pipeline (and marks
    /// it for cloud upload). A failure here is logged but does not block the
    /// confirm step. Persists ONLY on a detail-screen scan (a round exists to
    /// attach to). During CREATION the round doesn't exist yet, so we don't save
    /// an orphan, unattachable photo — the scanned DATA rides `scorecardData`;
    /// the card image is kept only when scanning from the round's detail screen.
    private func persistScorecardPhoto(_ image: UIImage) async {
        guard game != nil || practice != nil else { return }
        // Read relationships up front (before any await) so a concurrent delete
        // can't trap on access after suspension.
        let old = game?.scorecardPhoto ?? practice?.scorecardPhoto
        let season = game?.season ?? practice?.season
        do {
            // Replace any prior card so the old blob isn't orphaned against the
            // storage quota — clearing the flag alone would leak it.
            old?.delete(in: context)
            let photo = try await PhotoPersistenceService().savePhoto(
                image: image,
                context: context,
                athlete: athlete,
                game: game,
                practice: practice,
                season: season
            )
            photo.isScorecardPhoto = true
            photo.needsSync = true
            ErrorHandlerService.shared.saveContext(context, caller: "ScorecardScanFlow.persist")
        } catch {
            ErrorHandlerService.shared.handle(error, context: "Saving scorecard photo", showAlert: false)
        }
    }
}
