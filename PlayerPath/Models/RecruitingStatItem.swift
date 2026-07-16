//
//  RecruitingStatItem.swift
//  PlayerPath
//
//  One label/value pair rendered on a recruiting profile — a golf stat chip, a
//  self-entered measurable, or a contact row.
//
//  Every such pair is built exactly once (in RecruitingInfo's display helpers or
//  RecruitingGolfStats) and consumed twice: by the in-app preview and by the
//  publish snapshot that feeds the public web page. That's the whole point of the
//  type — the label text, the number formatting, and the ordering can't drift
//  between what an athlete previews and what a college coach opens.
//
//  `kind` carries the semantic identity so the SwiftUI layer can pick a chip
//  color without this type importing SwiftUI.
//

import Foundation

nonisolated struct RecruitingStatItem: Equatable {
    enum Kind: String {
        // Golf band
        case handicap, roundAvg, best, rounds
        case gir, fairways, putts, scrambling
        // Baseball / softball self-entered measurables
        case sixty, exitVelo, throwVelo, pitchVelo
        // Contact / academics
        case gpa, email, phone
    }

    let kind: Kind
    let label: String
    let value: String
}
