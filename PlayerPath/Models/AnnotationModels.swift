//
//  AnnotationModels.swift
//  PlayerPath
//
//  Models for the enhanced annotation system: categories, quick cues, drill cards.
//

import SwiftUI

// MARK: - Annotation Category

enum AnnotationCategory: String, Codable, CaseIterable {
    case mechanics
    case timing
    case approach
    case positive
    case correction

    var displayName: String {
        switch self {
        case .mechanics: return "Mechanics"
        case .timing: return "Timing"
        case .approach: return "Approach"
        case .positive: return "Positive"
        case .correction: return "Correction"
        }
    }

    var icon: String {
        switch self {
        case .mechanics: return "gearshape"
        case .timing: return "clock"
        case .approach: return "scope"
        case .positive: return "hand.thumbsup"
        case .correction: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .mechanics: return .blue
        case .timing: return .orange
        case .approach: return .purple
        case .positive: return .green
        case .correction: return .red
        }
    }
}

// MARK: - Quick Cue

struct QuickCue: Codable, Identifiable {
    var id: String?
    let text: String
    let category: String
    var usageCount: Int
    let createdAt: Date?

    var annotationCategory: AnnotationCategory? {
        AnnotationCategory(rawValue: category)
    }
}

// MARK: - Drill Card

struct DrillCard: Codable, Identifiable {
    var id: String?
    let coachID: String
    let coachName: String
    let templateType: String
    var categories: [DrillCardCategory]
    var overallRating: Int?
    var summary: String?
    let createdAt: Date?
    var updatedAt: Date?

    var template: DrillCardTemplate? {
        DrillCardTemplate(rawValue: templateType)
    }
}

struct DrillCardCategory: Codable {
    let name: String
    var rating: Int // 0-5 (0 = unrated)
    var notes: String?
}

enum DrillCardTemplate: String, Codable, CaseIterable {
    // Baseball / softball
    case battingReview = "batting_review"
    case pitchingReview = "pitching_review"
    case fieldingReview = "fielding_review"
    // Golf
    case fullSwing = "full_swing"
    case shortGame = "short_game"
    case putting
    case courseManagement = "course_management"
    case custom

    var displayName: String {
        switch self {
        case .battingReview: return "Batting Review"
        case .pitchingReview: return "Pitching Review"
        case .fieldingReview: return "Fielding Review"
        case .fullSwing: return "Full Swing"
        case .shortGame: return "Short Game"
        case .putting: return "Putting"
        case .courseManagement: return "Course Management"
        case .custom: return "Custom"
        }
    }

    /// Whether this template belongs to the golf sport family (used to group the picker).
    var isGolf: Bool {
        switch self {
        case .fullSwing, .shortGame, .putting, .courseManagement: return true
        default: return false
        }
    }

    var defaultCategories: [String] {
        switch self {
        case .battingReview:
            return ["Stance", "Load", "Swing Path", "Contact Point", "Follow Through"]
        case .pitchingReview:
            return ["Windup", "Arm Slot", "Release Point", "Follow Through", "Command"]
        case .fieldingReview:
            return ["Ready Position", "First Step", "Glove Work", "Throwing", "Footwork"]
        case .fullSwing:
            return ["Setup / Posture", "Takeaway", "Transition", "Impact", "Finish"]
        case .shortGame:
            return ["Setup", "Ball Position", "Contact", "Distance Control", "Trajectory"]
        case .putting:
            return ["Setup", "Stroke Path", "Face Control", "Speed / Distance", "Green Reading"]
        case .courseManagement:
            return ["Club Selection", "Shot Selection", "Tempo / Routine", "Decision Making", "Mental"]
        case .custom:
            return []
        }
    }
}
