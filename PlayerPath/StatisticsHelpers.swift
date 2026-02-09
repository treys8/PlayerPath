import Foundation
import SwiftData

/// A small helper to guarantee an Athlete has an attached AthleteStatistics object
/// and to provide a single place to record play results.
struct StatisticsHelpers {
    /// Maps a free-form hit type string to `PlayResultType` if recognized.
    /// Maintains a single source of truth for aliases.
    static func playResult(from hitType: String) -> PlayResultType? {
        let normalized = hitType.lowercased()
        let mapping: [String: PlayResultType] = [
            "single": .single, "1b": .single,
            "double": .double, "2b": .double,
            "triple": .triple, "3b": .triple,
            "homerun": .homeRun, "home run": .homeRun, "home_run": .homeRun, "hr": .homeRun,
            "walk": .walk, "bb": .walk,
            "strikeout": .strikeout, "k": .strikeout,
            "groundout": .groundOut, "ground out": .groundOut, "go": .groundOut,
            "flyout": .flyOut, "fly out": .flyOut, "fo": .flyOut,
            "ball": .ball,
            "strike": .strike,
            "hitbypitch": .hitByPitch, "hit by pitch": .hitByPitch, "hbp": .hitByPitch,
            "wildpitch": .wildPitch, "wild pitch": .wildPitch, "wp": .wildPitch,
            // Treat generic outs as ground outs by convention unless the caller is explicit.
            "out": .groundOut
        ]
        return mapping[normalized]
    }

    /// Ensures the athlete has an AthleteStatistics object. If missing, creates and inserts one.
    /// - Parameters:
    ///   - athlete: The athlete to ensure stats for.
    ///   - modelContext: The SwiftData model context used to insert/save.
    /// - Returns: The attached AthleteStatistics object.
    static func ensureStatistics(for athlete: Athlete, in modelContext: ModelContext) -> AthleteStatistics {
        if let stats = athlete.statistics { return stats }
        let stats = AthleteStatistics()
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
        // Map the string to a strongly-typed play result and delegate to the single source of truth.
        guard let result = playResult(from: hitType) else {
            assertionFailure("Unknown hitType: \(hitType)")
            return
        }
        // Delegate to the strongly-typed path to avoid duplication.
        record(playResult: result, for: athlete, in: modelContext)
    }

    /// Records a play result using the strongly-typed PlayResultType.
    private static func record(playResult: PlayResultType, for athlete: Athlete, in modelContext: ModelContext) {
        let stats = ensureStatistics(for: athlete, in: modelContext)
        stats.addPlayResult(playResult)
        stats.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save modelContext: \(error)")
        }
    }

    /// Convenience that maps a string to PlayResultType and records it if possible.
    @discardableResult
    static func recordIfPossible(hitType: String, for athlete: Athlete, in modelContext: ModelContext) -> Bool {
        guard let result = playResult(from: hitType) else {
            assertionFailure("Unknown hitType: \(hitType)")
            return false
        }
        record(playResult: result, for: athlete, in: modelContext)
        return true
    }
}
