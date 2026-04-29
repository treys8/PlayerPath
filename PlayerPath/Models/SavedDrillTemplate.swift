//
//  SavedDrillTemplate.swift
//  PlayerPath
//
//  A coach-saved drill card template. Stored under
//  `coachTemplates/{coachID}/drillCardTemplates/{templateID}`.
//
//  Distinct from the built-in `DrillCardTemplate` enum (the canonical types
//  Batting/Pitching/Fielding/Custom) — a SavedDrillTemplate captures a coach's
//  customized category list + optional default summary as a reusable preset.
//

import Foundation

struct SavedDrillTemplate: Codable, Identifiable {
    var id: String?
    let name: String
    let templateType: String
    let categoryNames: [String]
    var defaultSummary: String?
    var usageCount: Int
    let createdAt: Date?
}
