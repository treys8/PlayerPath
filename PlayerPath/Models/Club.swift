//
//  Club.swift
//  PlayerPath
//

import SwiftUI

/// Golf club tag for a `VideoClip`. Mirrors `PlayResultType` in shape — a tag
/// recorded at clip-save time and displayed in clip rows / thumbnails. Stored
/// directly on `VideoClip.club` as a Codable enum (SchemaV23).
///
/// On the Firestore wire the value is the rawValue string (e.g. "7i"); decode
/// with `Club(rawValue:)`. A clip has either a `playResult` (baseball/softball)
/// or a `club` (golf), never both — see `VideoClip.isTagged`.
enum Club: String, CaseIterable, Codable {
    case driver = "Driver"
    case wood3 = "3W"
    case wood5 = "5W"
    case hybrid = "Hybrid"
    case iron3 = "3i"
    case iron4 = "4i"
    case iron5 = "5i"
    case iron6 = "6i"
    case iron7 = "7i"
    case iron8 = "8i"
    case iron9 = "9i"
    case pw = "PW"
    case gw = "GW"
    case sw = "SW"
    case lw = "LW"
    case putter = "Putter"

    var displayName: String { rawValue }

    /// Compact label for dense pickers (the shot-entry club grid). Woods/irons/
    /// wedges already read short ("3W", "7i", "PW"); only the full-word cases
    /// need shortening.
    var shortName: String {
        switch self {
        case .driver: return "Dr"
        case .hybrid: return "Hy"
        case .putter: return "Pt"
        default:      return rawValue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .driver: return "Driver"
        case .wood3:  return "3 Wood"
        case .wood5:  return "5 Wood"
        case .hybrid: return "Hybrid"
        case .iron3:  return "3 Iron"
        case .iron4:  return "4 Iron"
        case .iron5:  return "5 Iron"
        case .iron6:  return "6 Iron"
        case .iron7:  return "7 Iron"
        case .iron8:  return "8 Iron"
        case .iron9:  return "9 Iron"
        case .pw:     return "Pitching Wedge"
        case .gw:     return "Gap Wedge"
        case .sw:     return "Sand Wedge"
        case .lw:     return "Lob Wedge"
        case .putter: return "Putter"
        }
    }

    enum Category: CaseIterable {
        case wood, iron, wedge, putter

        var displayName: String {
            switch self {
            case .wood:   return "WOODS"
            case .iron:   return "IRONS"
            case .wedge:  return "WEDGES"
            case .putter: return "PUTTER"
            }
        }

        var color: Color {
            switch self {
            case .wood:   return .brandGold
            case .iron:   return .brandNavy
            case .wedge:  return .green
            case .putter: return .purple
            }
        }

        var iconName: String {
            switch self {
            case .wood:   return "flame.fill"
            case .iron:   return "scope"
            case .wedge:  return "target"
            case .putter: return "flag.fill"
            }
        }
    }

    var category: Category {
        switch self {
        case .driver, .wood3, .wood5, .hybrid:
            return .wood
        case .iron3, .iron4, .iron5, .iron6, .iron7, .iron8, .iron9:
            return .iron
        case .pw, .gw, .sw, .lw:
            return .wedge
        case .putter:
            return .putter
        }
    }

    /// Clubs in display order grouped by category. Used by the recording overlay
    /// and the retro-tag editor to lay out picker sections.
    static func cases(in category: Category) -> [Club] {
        allCases.filter { $0.category == category }
    }
}
