//
//  ShotClubRecommender.swift
//  PlayerPath
//
//  v1 club-suggestion heuristic for shot-by-shot entry: surfaces ~4 likely
//  clubs (★) while the full bag stays available. Pure and standalone so v2 can
//  swap in a distance-/history-aware recommender without touching the view.
//
//  When a rangefinder distance is present it drives the pick; otherwise the lie
//  does. The result is an ORDER-PRESERVING set of "recommended" clubs — the view
//  highlights these but never hides the rest.
//

import Foundation

enum ShotClubRecommender {

    /// Up to four recommended clubs for a shot from `lie` on a hole of `par`,
    /// optionally informed by yards-to-hole. Returned as a set for O(1) "is this
    /// recommended?" lookups in the picker.
    static func recommended(lie: ShotLie, par: Int, distanceBefore: Int?) -> Set<Club> {
        if let yards = distanceBefore {
            return Set(byDistance(yards))
        }
        return Set(byLie(lie, par: par))
    }

    private static func byDistance(_ yards: Int) -> [Club] {
        switch yards {
        case 220...:     return [.driver, .wood3, .hybrid, .wood5]
        case 180..<220:  return [.iron4, .iron5, .hybrid, .iron6]
        case 150..<180:  return [.iron6, .iron7, .iron5, .iron8]
        case 120..<150:  return [.iron8, .iron9, .iron7, .pw]
        case 80..<120:   return [.pw, .gw, .iron9, .sw]
        default:         return [.sw, .lw, .gw, .pw]   // <80 yds
        }
    }

    /// A typical amateur carry distance (yards) for `club`, used to seed the
    /// yards-to-pin wheel so picking a club lands the picker near the right number
    /// — a wedge opens around 90, a long iron around 190, so it's a short flick
    /// either way instead of scrolling from a flat default. Values are the inverse
    /// of the `byDistance` buckets above, so the two stay mutually consistent.
    ///
    /// This is the seam for a future history-aware default: swap this for the
    /// athlete's own average recorded `distanceBefore` per club, falling back here
    /// on cold start — no caller changes needed.
    static func typicalYardage(for club: Club) -> Int {
        switch club {
        case .driver: return 230
        case .wood3:  return 210
        case .wood5:  return 195
        case .hybrid: return 190
        case .iron3:  return 190
        case .iron4:  return 180
        case .iron5:  return 170
        case .iron6:  return 160
        case .iron7:  return 150
        case .iron8:  return 140
        case .iron9:  return 130
        case .pw:     return 120
        case .gw:     return 105
        case .sw:     return 90
        case .lw:     return 70
        case .putter: return 10   // no approach pill opens for a putter; sane floor only
        }
    }

    private static func byLie(_ lie: ShotLie, par: Int) -> [Club] {
        switch lie {
        case .tee:
            // Par 3 is an approach off the tee — suggest mid irons, not woods.
            return par == 3 ? [.iron7, .iron6, .iron8, .iron5]
                            : [.driver, .wood3, .hybrid, .wood5]
        case .fairway, .rough, .recovery, .water:
            return [.iron7, .iron6, .iron8, .iron9]
        case .sand:
            return [.sw, .lw, .gw, .pw]
        case .fringe:
            return [.pw, .gw, .putter, .sw]
        case .green:
            return [.putter]
        }
    }
}
