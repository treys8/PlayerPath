//
//  GolfCaptureContext.swift
//  PlayerPath
//
//  Holds the "current hole" for casual golf capture — recording swings on a
//  course WITHOUT starting a live, scored round. The recorder shows a stepper
//  (CurrentHoleStepper) bound to this; ClipPersistenceService.saveClip reads it
//  to stamp each clip's hole and to route the clip into today's practice round
//  (when a hole is set) vs range session (when nil).
//
//  Transient / in-memory by design: it survives backgrounding while the app is
//  warm but resets on a cold launch. That's acceptable because the stepper is
//  always visible during capture, so a stale value is correctable rather than
//  silent. (A persisted pointer is a possible later refinement.)
//

import Foundation
import Observation

@MainActor
@Observable
final class GolfCaptureContext {
    static let shared = GolfCaptureContext()
    private init() {}

    /// The hole the next casually-recorded golf clip is stamped with, or nil for
    /// a range session (no hole).
    var currentHole: Int?

    /// Upper bound for the stepper — a casual round is assumed to be 18 holes.
    let holeCount = 18

    /// Bump to the next hole. nil ("Range") advances to hole 1; otherwise +1
    /// capped at `holeCount`.
    func increment() {
        if let hole = currentHole {
            currentHole = min(hole + 1, holeCount)
        } else {
            currentHole = 1
        }
    }

    /// Step back a hole. Decrementing below hole 1 returns to nil ("Range").
    func decrement() {
        guard let hole = currentHole else { return }
        currentHole = hole <= 1 ? nil : hole - 1
    }
}
