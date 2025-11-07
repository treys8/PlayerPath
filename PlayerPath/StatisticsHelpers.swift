import Foundation
import SwiftData

/// A small helper to guarantee an Athlete has an attached Statistics object
/// and to provide a single place to record play results.
struct StatisticsHelpers {
    /// Ensures the athlete has a Statistics object. If missing, creates and inserts one.
    /// - Parameters:
    ///   - athlete: The athlete to ensure stats for.
    ///   - modelContext: The SwiftData model context used to insert/save.
    /// - Returns: The attached Statistics object.
    static func ensureStatistics(for athlete: Athlete, in modelContext: ModelContext) -> Statistics {
        if let stats = athlete.statistics { return stats }
        let stats = Statistics()
        // Establish relationships (adjust if your model uses different names)
        athlete.statistics = stats
        stats.athlete = athlete
        modelContext.insert(stats)
        return stats
    }

    /// Records a hit result, updating statistics accordingly and saving.
    /// - Parameters:
    ///   - hitType: Expected values: "single", "double", "triple", "homeRun" (or aliases), "out".
    ///   - athlete: The athlete whose stats to update.
    ///   - modelContext: The SwiftData model context used to save changes.
    static func record(hitType: String, for athlete: Athlete, in modelContext: ModelContext) {
        let stats = ensureStatistics(for: athlete, in: modelContext)
        switch hitType.lowercased() {
        case "single":
            stats.singles += 1
            stats.hits += 1
            stats.atBats += 1
        case "double":
            stats.doubles += 1
            stats.hits += 1
            stats.atBats += 1
        case "triple":
            stats.triples += 1
            stats.hits += 1
            stats.atBats += 1
        case "homerun", "homeRun", "hr":
            stats.homeRuns += 1
            stats.hits += 1
            stats.atBats += 1
        case "out":
            stats.atBats += 1
        default:
            break
        }
        do { try modelContext.save() } catch { print("🔴 Failed saving stats: \(error)") }
    }
}
