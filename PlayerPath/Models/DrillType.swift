//
//  DrillType.swift
//  PlayerPath
//
//  Shared drill / focus taxonomy for both the coach VideoTagEditor (clip
//  `drillType`) and athlete practice logging (`Practice.drillTypes`). Extracted
//  here so practice views don't depend on coach UI files. Persisted as String
//  rawValues, so the catalog can grow without a schema change.
//

import Foundation

// MARK: - Baseball / Softball drills

enum DrillType: String, CaseIterable {
    case battingPractice = "batting_practice"
    case teeWork = "tee_work"
    case softToss = "soft_toss"
    case liveBP = "live_bp"
    case bullpen = "bullpen"
    case fieldingDrill = "fielding_drill"
    case catchPlay = "catch_play"
    case baseRunning = "base_running"
    case situational = "situational"

    var displayName: String {
        switch self {
        case .battingPractice: return "Batting Practice"
        case .teeWork: return "Tee Work"
        case .softToss: return "Soft Toss"
        case .liveBP: return "Live BP"
        case .bullpen: return "Bullpen"
        case .fieldingDrill: return "Fielding Drill"
        case .catchPlay: return "Catch & Play"
        case .baseRunning: return "Base Running"
        case .situational: return "Situational"
        }
    }

    var icon: String {
        switch self {
        case .battingPractice: return "figure.baseball"
        case .teeWork: return "circle.grid.cross"
        case .softToss: return "arrow.up.forward"
        case .liveBP: return "figure.baseball"
        case .bullpen: return "baseball"
        case .fieldingDrill: return "baseball.diamond.bases"
        case .catchPlay: return "arrow.left.arrow.right"
        case .baseRunning: return "figure.run"
        case .situational: return "list.bullet.clipboard"
        }
    }
}

// MARK: - Golf drills

enum GolfDrillType: String, CaseIterable {
    case drivingRange = "driving_range"
    case fullSwing = "full_swing"
    case shortGame = "short_game"
    case chipping = "chipping"
    case pitching = "pitching_golf"
    case bunker = "bunker"
    case putting = "putting"
    case coursePlay = "course_play"

    var displayName: String {
        switch self {
        case .drivingRange: return "Driving Range"
        case .fullSwing:    return "Full Swing"
        case .shortGame:    return "Short Game"
        case .chipping:     return "Chipping"
        case .pitching:     return "Pitching"
        case .bunker:       return "Bunker"
        case .putting:      return "Putting"
        case .coursePlay:   return "Course Play"
        }
    }

    var icon: String {
        switch self {
        case .drivingRange: return "figure.golf"
        case .fullSwing:    return "figure.golf"
        case .shortGame:    return "flag.fill"
        case .chipping:     return "arrow.up.forward"
        case .pitching:     return "arrow.up.right"
        case .bunker:       return "mountain.2.fill"
        case .putting:      return "flag.circle.fill"
        case .coursePlay:   return "map.fill"
        }
    }
}

// MARK: - Sport-agnostic focus option

/// A single, sport-resolved drill/focus choice the UI can render and select
/// without caring which underlying enum produced it. Identity is the stored
/// `rawValue`.
struct PracticeFocusOption: Identifiable, Hashable {
    let rawValue: String
    let displayName: String
    let icon: String

    var id: String { rawValue }
}

enum PracticeFocusCatalog {
    /// The selectable focus options for a sport. Golf practices draw from
    /// `GolfDrillType`; baseball/softball from `DrillType`.
    static func options(for sport: Sport) -> [PracticeFocusOption] {
        switch sport {
        case .golf:
            return GolfDrillType.allCases.map {
                PracticeFocusOption(rawValue: $0.rawValue, displayName: $0.displayName, icon: $0.icon)
            }
        case .baseball, .softball:
            return DrillType.allCases.map {
                PracticeFocusOption(rawValue: $0.rawValue, displayName: $0.displayName, icon: $0.icon)
            }
        }
    }

    /// Human-readable name for a stored rawValue, resolving across both
    /// taxonomies (so a tag survives even if the practice's sport changes).
    static func displayName(for rawValue: String) -> String {
        DrillType(rawValue: rawValue)?.displayName
            ?? GolfDrillType(rawValue: rawValue)?.displayName
            ?? rawValue
    }

    /// SF Symbol for a stored rawValue, resolving across both taxonomies.
    static func icon(for rawValue: String) -> String {
        DrillType(rawValue: rawValue)?.icon
            ?? GolfDrillType(rawValue: rawValue)?.icon
            ?? "tag.fill"
    }
}

// MARK: - Practice accessor

extension Practice {
    /// Selected focus rawValues, split/joined over the stored comma string in
    /// `drillTypes`. Empty selection clears the field to nil.
    var drillFocusRawValues: [String] {
        get {
            (drillTypes ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            drillTypes = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    /// Display names for the selected focuses, resolved across both taxonomies.
    var drillFocusDisplayNames: [String] {
        drillFocusRawValues.map { PracticeFocusCatalog.displayName(for: $0) }
    }
}
