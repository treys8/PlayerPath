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

    private static func byLie(_ lie: ShotLie, par: Int) -> [Club] {
        switch lie {
        case .tee:
            // Par 3 is an approach off the tee — suggest mid irons, not woods.
            return par == 3 ? [.iron7, .iron6, .iron8, .iron5]
                            : [.driver, .wood3, .hybrid, .wood5]
        case .fairway, .rough, .recovery:
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
