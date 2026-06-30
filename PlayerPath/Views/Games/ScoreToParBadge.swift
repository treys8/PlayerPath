//
//  ScoreToParBadge.swift
//  PlayerPath
//
//  Classic golf score-to-par notation, shared by every scorecard cell so the
//  treatment is identical everywhere: the score number inside a circle (under
//  par) or square (over par), doubled for eagle-or-better / double-bogey-or-worse,
//  tinted green (under) or red (over). Par renders as a plain neutral number with
//  no shape. Driven purely by `diff = score - par`, so it works off a HoleScore,
//  a local HoleEntry, or any (score, par) pair without a model instance.
//

import SwiftUI

/// Score-to-par category derived from `diff = score - par`. Eagle-and-better
/// (including an ace / albatross) collapse to the double-circle bucket;
/// double-bogey-and-worse to the double-square bucket — mirroring the grouping
/// in `HoleScore.diffLabel`.
enum ScoreNotation {
    case eagleOrBetter, birdie, par, bogey, doubleOrWorse

    init(diff: Int) {
        switch diff {
        case ...(-2): self = .eagleOrBetter
        case -1:      self = .birdie
        case 0:       self = .par
        case 1:       self = .bogey
        default:      self = .doubleOrWorse   // >= 2
        }
    }

    /// Number/shape tint — reuses the app's single par-relative scale
    /// (green under, red over, neutral at par).
    var tint: Color {
        switch self {
        case .eagleOrBetter, .birdie: return .parRelative(-1)
        case .par:                    return .parRelative(0)
        case .bogey, .doubleOrWorse:  return .parRelative(1)
        }
    }

    /// Faint cell-background wash so a round's shape reads at a glance. Par gets
    /// no wash (neutral) — only under/over holes tint, matching the house
    /// 0.10-opacity fill convention.
    var wash: Color {
        switch self {
        case .par: return Color(.secondarySystemBackground)
        default:   return tint.opacity(0.10)
        }
    }

    fileprivate var isCircle: Bool { self == .eagleOrBetter || self == .birdie }
    fileprivate var isSquare: Bool { self == .bogey || self == .doubleOrWorse }
    fileprivate var isDouble: Bool { self == .eagleOrBetter || self == .doubleOrWorse }
}

/// The score number wrapped in its par-relative notation. Outline shapes only
/// (never filled) so the number stays the legible hero.
struct ScoreToParBadge: View {
    let score: Int
    let par: Int
    var numberFont: Font = .headingMedium
    var diameter: CGFloat = 30

    private var note: ScoreNotation { ScoreNotation(diff: score - par) }

    var body: some View {
        Text("\(score)")
            .font(numberFont)
            .monospacedDigit()
            .foregroundColor(note.tint)
            .frame(width: diameter, height: diameter)
            .overlay { notation }
    }

    @ViewBuilder private var notation: some View {
        ZStack {
            if note.isCircle {
                Circle().stroke(note.tint, lineWidth: 1.5)
                if note.isDouble {
                    Circle().inset(by: 3).stroke(note.tint, lineWidth: 1.5)
                }
            } else if note.isSquare {
                RoundedRectangle(cornerRadius: 4).stroke(note.tint, lineWidth: 1.5)
                if note.isDouble {
                    RoundedRectangle(cornerRadius: 3).inset(by: 3).stroke(note.tint, lineWidth: 1.5)
                }
            }
        }
    }
}

#Preview {
    // Par 4 across the scoring range: 2=eagle (◎), 3=birdie (○), 4=par,
    // 5=bogey (□), 6=double (⊡), plus a 1 (ace → ◎).
    HStack(spacing: 12) {
        ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { s in
            ScoreToParBadge(score: s, par: 4)
        }
    }
    .padding()
}
