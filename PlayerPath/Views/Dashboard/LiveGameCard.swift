//
//  LiveGameCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

/// Tournament-style live card. Renders a live golf tournament / baseball game
/// (a `Game`) OR a live golf practice round (a `Practice`) — they share the
/// same scoring chrome (running score, "Score Hole X" CTA, End). Range
/// sessions use the lighter `LiveSessionCard` instead.
struct LiveGameCard: View {
    /// XOR parent — exactly one is set at construction. Mirrors
    /// `ScoreHoleSheet.Parent`; lets the body switch on small accessors
    /// rather than duplicating ~250 lines for the practice-round case.
    private enum Parent {
        case game(Game)
        case practiceRound(Practice)
    }
    private let parent: Parent
    private let isEnding: Bool
    /// Set on golf live activities to surface a "Score Hole X" CTA inside the
    /// card. Tapped without bubbling up to the parent NavigationLink, so the
    /// user can score the current hole without navigating into the detail
    /// screen.
    private let onScore: (() -> Void)?
    private let onEnd: (() -> Void)?

    init(game: Game, isEnding: Bool = false, onScore: (() -> Void)? = nil, onEnd: (() -> Void)? = nil) {
        self.parent = .game(game)
        self.isEnding = isEnding
        self.onScore = onScore
        self.onEnd = onEnd
    }

    init(practiceRound practice: Practice, isEnding: Bool = false, onScore: (() -> Void)? = nil, onEnd: (() -> Void)? = nil) {
        self.parent = .practiceRound(practice)
        self.isEnding = isEnding
        self.onScore = onScore
        self.onEnd = onEnd
    }

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Parent accessors

    private var isGolf: Bool {
        switch parent {
        case .game(let g):     return g.season?.sport == .golf
        case .practiceRound:   return true
        }
    }

    /// Per-hole rows for this activity, sorted ascending. Empty when none yet.
    private var scoredHoles: [HoleScore] {
        let holes: [HoleScore]
        switch parent {
        case .game(let g):          holes = g.holeScores ?? []
        case .practiceRound(let p): holes = p.holeScores ?? []
        }
        return holes.sorted { $0.holeNumber < $1.holeNumber }
    }

    private var totalHoles: Int {
        switch parent {
        case .game(let g):          return g.holes ?? 18
        case .practiceRound(let p): return p.holes ?? 18
        }
    }

    /// Total score — games persist one; practice rounds derive from holes only.
    private var totalScore: Int? {
        switch parent {
        case .game(let g):     return g.totalScore
        case .practiceRound:   return nil
        }
    }

    private var coursePar: Int? {
        switch parent {
        case .game(let g):     return g.par
        case .practiceRound:   return nil
        }
    }

    private var baseballStats: GameStatistics? {
        switch parent {
        case .game(let g):     return g.gameStats
        case .practiceRound:   return nil
        }
    }

    private var date: Date? {
        switch parent {
        case .game(let g):          return g.date
        case .practiceRound(let p): return p.date
        }
    }

    private var iconName: String { isGolf ? "figure.golf" : "baseball.fill" }

    private var typeLabel: String {
        switch parent {
        case .game:            return isGolf ? "TOURNAMENT" : "GAME"
        case .practiceRound:   return "PRACTICE ROUND"
        }
    }

    /// Headline line. Tournaments show "at/vs opponent"; practice rounds show
    /// the course when set, otherwise the hole count (the type is already on
    /// the label line).
    private var titleText: String {
        switch parent {
        case .game(let g):
            return "\(isGolf ? "at" : "vs") \(g.opponent.isEmpty ? "Unknown" : g.opponent)"
        case .practiceRound(let p):
            if let course = p.course, !course.trimmingCharacters(in: .whitespaces).isEmpty {
                return course
            }
            return "\(totalHoles) Holes"
        }
    }

    private var endLabel: String { isGolf ? "End Round" : "End" }

    /// Next unscored hole, capped at total. Used to label the "Score Hole X" CTA.
    private var nextHoleNumber: Int {
        let scoredMax = scoredHoles.last?.holeNumber ?? 0
        return min(scoredMax + 1, totalHoles)
    }

    /// Sum of per-hole strokes — used for the live progress label when at
    /// least one hole has been scored.
    private var runningScore: Int { scoredHoles.reduce(0) { $0 + $1.score } }
    private var runningPar: Int { scoredHoles.reduce(0) { $0 + $1.par } }
    private var runningDiff: Int { runningScore - runningPar }
    private var runningDiffLabel: String {
        if runningDiff == 0 { return "E" }
        return runningDiff > 0 ? "+\(runningDiff)" : "\(runningDiff)"
    }

    /// True when the card has at least one CTA to render in its action row.
    private var hasActions: Bool {
        (isGolf && onScore != nil) || onEnd != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: live indicator, info, and navigation chevron. The info
            // column gets the full card width here so the LIVE badge and title
            // never compete with the action buttons for space.
            HStack(spacing: 14) {
                // Enhanced pulsing indicator with glow
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(Color.red.opacity(isPulsing ? 0.15 : 0.25))
                        .frame(width: 50, height: 50)
                        .blur(radius: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(Color.red.opacity(isPulsing ? 0.1 : 0.35))
                        .frame(width: 36, height: 36)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                        .symbolRenderingMode(.hierarchical)
                }
                .onAppear { if !reduceMotion { isPulsing = true } }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        if !reduceMotion { isPulsing = true }
                    } else {
                        isPulsing = false
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // Animated LIVE badge
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .opacity(isPulsing ? 0.5 : 1.0)

                            Text("LIVE")
                                .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                                .foregroundColor(.red)
                                .fixedSize()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.12))
                        )
                        // Keep the pill at its intrinsic width so "LIVE" can never
                        // wrap to "LIV E" when the row is tight.
                        .fixedSize()

                        Text(typeLabel)
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(titleText)
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Show stats if available
                    if isGolf, !scoredHoles.isEmpty {
                        // Live progress — preferred whenever per-hole entries exist.
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .font(.caption2)
                            Text("Hole \(scoredHoles.last?.holeNumber ?? 0) of \(totalHoles)")
                                .font(.bodySmall)
                                .monospacedDigit()
                            Text("· \(runningDiffLabel)")
                                .font(.bodySmall)
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                    } else if isGolf, let score = totalScore {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .font(.caption2)
                            Text("\(score)")
                                .font(.bodySmall)
                                .monospacedDigit()
                            if let par = coursePar {
                                let diff = score - par
                                Text(diff == 0 ? "(E)" : (diff > 0 ? "(+\(diff))" : "(\(diff))"))
                                    .font(.bodySmall)
                                    .monospacedDigit()
                            }
                        }
                        .foregroundColor(.secondary)
                    } else if !isGolf, let stats = baseballStats, stats.atBats > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                            Text("\(stats.hits)-for-\(stats.atBats)")
                                .font(.bodySmall)
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                    } else if let date = date {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                            Text(date, format: .dateTime.hour().minute())
                                .font(.bodySmall)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Action row — full-width CTAs on their own line so they never
            // crowd the title. Side-by-side and equal width when both present.
            if hasActions {
                HStack(spacing: 10) {
                    if isGolf, let onScore {
                        // Primary CTA for live golf activities — score the
                        // current hole without navigating into the detail screen.
                        Button {
                            Haptics.medium()
                            onScore()
                        } label: {
                            Text("Score Hole \(nextHoleNumber)")
                                .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    LinearGradient(
                                        colors: [.brandNavy, .brandNavy.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: .brandNavy.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.borderless)
                    }

                    if let onEnd {
                        // End button with gradient
                        Button {
                            Haptics.medium()
                            onEnd()
                        } label: {
                            Group {
                                if isEnding {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(endLabel)
                                }
                            }
                            .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .disabled(isEnding)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.1), Color.red.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(Color.red.opacity(0.4), lineWidth: 2)
        )
        .shadow(color: .red.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
