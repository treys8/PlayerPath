import Foundation

/// Read-only answers to "is any golf activity live for this athlete?" and a
/// short noun for the confirmation copy. Backs the golf-only single-live
/// confirmation surfaced before starting a new tournament / practice round /
/// range session. Games on the baseball side are ignored — baseball keeps its
/// long-shipped silent auto-end in `GameService`.
@MainActor
enum LiveActivityGuard {

    /// The athlete's live golf tournament, if any.
    static func liveGolfGame(for athlete: Athlete) -> Game? {
        (athlete.games ?? []).first { $0.isLive && $0.season?.sport == .golf }
    }

    /// The athlete's live golf practice (round or range session), if any.
    static func liveGolfPractice(for athlete: Athlete) -> Practice? {
        (athlete.practices ?? []).first { $0.isLive }
    }

    /// True when a golf tournament OR practice is currently live.
    static func hasAnyLiveGolf(for athlete: Athlete) -> Bool {
        liveGolfGame(for: athlete) != nil || liveGolfPractice(for: athlete) != nil
    }

    /// Short noun for the confirmation dialog body, e.g. "tournament",
    /// "practice round", "range session". Nil when nothing is live.
    static func currentLiveGolfLabel(for athlete: Athlete) -> String? {
        if liveGolfGame(for: athlete) != nil { return "tournament" }
        if let practice = liveGolfPractice(for: athlete) {
            return practice.practiceType == PracticeType.rangeSession.rawValue
                ? "range session"
                : "practice round"
        }
        return nil
    }
}
