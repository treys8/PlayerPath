//
//  BulkImportOutcome.swift
//  PlayerPath
//
//  Result of one bulk-import run, shared by the video and photo pipelines.
//  Replaces the loose tuple the video path used to pass around: the import can
//  now end for reasons the caller has to act on (storage full → offer an
//  upgrade and resume the remainder), which needs more than a count of wins.
//

import Foundation
import SwiftUI
import PhotosUI

/// Outcome of a single bulk-import run.
///
/// Deliberately NOT `Sendable`: `resumeSeason` is a `@Model`, which is not
/// `Sendable` and must never cross an actor boundary. This value travels only
/// between `@MainActor` SwiftUI views.
struct BulkImportOutcome: Equatable {

    // MARK: Counts

    /// Items that produced a live row.
    var succeeded = 0
    /// Items that were loaded but could not be persisted (validation, save error).
    var failed = 0
    /// Items skipped because their dedupe key was already claimed — either by an
    /// earlier import or by an earlier item in this same batch.
    var skippedDuplicates = 0
    /// Items whose source bytes could not be loaded from the Photos library at
    /// all. Tracked apart from `failed` because an all-load-failure run means the
    /// picker selection went stale, not that the media is bad. See `allLoadsFailed`.
    var loadFailures = 0

    // MARK: Termination

    /// The run stopped early because the athlete's projected cloud storage was
    /// exhausted. The caller must present the upgrade sheet rather than a toast.
    var stoppedForQuota = false
    /// The user cancelled mid-run (or before starting).
    var wasCancelled = false

    // MARK: Sizes

    /// Bytes actually committed by this run — what `reservedThisSession`
    /// accumulated, so upgrade copy can quote a real number.
    var importedBytes: Int64 = 0
    /// Size of the single item that tripped the storage gate. Always known when
    /// `stoppedForQuota` is true, even when `succeeded == 0`, so the sheet can
    /// state at least one certain figure instead of an invented total.
    var blockedItemBytes: Int64 = 0

    // MARK: Resume payload

    /// Items that never ran, in original order — the first entry is the one that
    /// tripped the gate. Empty in every non-quota outcome.
    ///
    /// KNOWN LIMITATION: `PhotosPickerItem` is a session-scoped token, not a
    /// durable reference. Holding it across a StoreKit purchase (which can
    /// background the app, and under Limited Photos access lets the user change
    /// the selection) can leave it unresolvable. That case surfaces as
    /// `allLoadsFailed`, not as a pile of failures — see `wasResume`.
    var remaining: [PhotosPickerItem] = []
    /// Season the interrupted run was filing to, so the resumed run files the
    /// remainder identically.
    var resumeSeason: Season?
    /// The season choice was already made (explicitly or by confirming
    /// match-by-date), so the resumed run must not re-ask. Kept separate from
    /// `resumeSeason` because "match by date" is a real confirmed choice whose
    /// season is legitimately nil.
    var seasonWasConfirmed = false
    /// This run WAS itself a resume. Only meaningful for interpreting
    /// `allLoadsFailed`, and for keeping analytics from double-counting one user
    /// action as two imports.
    var wasResume = false

    /// The storage snapshot this run gated on. Carried so the storage-full sheet
    /// can quote it without taking a second snapshot — building one walks every
    /// athlete's clips and photos on the main actor, which is not something to do
    /// twice for one import.
    var storageSnapshot: ProjectedCloudStorage.Snapshot?

    // MARK: Derived

    /// Total items the run was handed.
    var attempted: Int { succeeded + failed + skippedDuplicates + loadFailures }

    /// Every item failed at the load step and nothing else happened — the
    /// signature of a stale picker selection rather than of bad media. Drives
    /// "pick them again" copy instead of an alarming failure count.
    var allLoadsFailed: Bool {
        loadFailures > 0 && succeeded == 0 && skippedDuplicates == 0 && failed == 0
    }
}

// MARK: - Result copy

/// Severity of a bulk-import result toast. Shared by both pipelines so the photo
/// and video paths cannot drift apart in how they report the same outcome.
enum BulkImportToastKind {
    case success, warning, error

    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return Theme.warning
        case .error:   return .red
        }
    }
}

extension BulkImportOutcome {
    /// Toast copy for every outcome a caller handles inline.
    ///
    /// Returns nil for `stoppedForQuota` — that case gets `ImportStorageFullSheet`,
    /// not a toast. A 2.5-second gray toast was the old dead end this whole change
    /// exists to remove, so the type refuses to produce one.
    ///
    /// - Parameters:
    ///   - mediaNoun: singular, e.g. "video" or "photo".
    ///   - eventNoun: singular lowercase name of the event this import was
    ///     attached to ("game", "round", "practice"), or nil for a library-level
    ///     import. Six of the nine call sites carry an event, and there a skipped
    ///     duplicate means something quite different: the asset is in the library
    ///     but was NOT added to this event, which is what the user was trying to
    ///     do. Saying only "already in your library" is true and useless.
    func toastCopy(mediaNoun: String, eventNoun: String? = nil) -> (text: String, kind: BulkImportToastKind)? {
        if stoppedForQuota { return nil }

        let plural = mediaNoun + "s"
        // Every branch that reports a count reports skips too. Omitting them
        // under-reports what the run did and makes a de-duplicated batch look
        // like it silently lost items.
        let skipNote: String
        if skippedDuplicates == 0 {
            skipNote = ""
        } else if eventNoun != nil {
            skipNote = ", \(skippedDuplicates) already imported (not added)"
        } else {
            skipNote = ", \(skippedDuplicates) already imported"
        }

        if wasCancelled {
            if succeeded > 0 {
                return ("Cancelled — \(succeeded) imported\(skipNote)", .warning)
            }
            return (skippedDuplicates > 0
                    ? "Cancelled — \(skippedDuplicates) already imported"
                    : "Import cancelled", .warning)
        }

        // The whole batch was already in the library. This used to fall through
        // to "Import failed" — both wrong and alarming for the single most likely
        // outcome of a second backfill sitting over an overlapping selection.
        if succeeded == 0 && failed == 0 && loadFailures == 0 && skippedDuplicates > 0 {
            // Inside a game/practice the library-level wording would answer a
            // question the user didn't ask. Tell them the actual outcome — nothing
            // was added here — and where to go to fix it.
            if let eventNoun {
                let lead = skippedDuplicates == 1
                    ? "Already imported"
                    : "All \(skippedDuplicates) already imported"
                return ("\(lead) — not added to this \(eventNoun). Tag them from the \(plural.capitalized) tab.", .warning)
            }
            return (skippedDuplicates == 1
                    ? "Already in your library"
                    : "All \(skippedDuplicates) already in your library", .success)
        }

        if allLoadsFailed {
            return ("Selection expired — pick them again", .warning)
        }

        let failures = failed + loadFailures
        if failures == 0 && succeeded > 0 {
            let base = succeeded == 1 ? "1 \(mediaNoun) imported" : "\(succeeded) \(plural) imported"
            return (base + skipNote, .success)
        }
        if succeeded == 0 {
            return (skippedDuplicates > 0 ? "Nothing imported\(skipNote)" : "Import failed", .error)
        }
        return ("\(succeeded) imported, \(failures) failed\(skipNote)", .warning)
    }
}
