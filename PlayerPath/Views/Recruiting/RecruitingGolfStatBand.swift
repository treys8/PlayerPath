//
//  RecruitingGolfStatBand.swift
//  PlayerPath
//
//  Golf is the recruiting-stats exception: scoring is objective and IS the
//  recruiting currency, so golf profiles carry a full stat band. Derived LIVE
//  from the same sources as the in-app Stats screen (HandicapEstimator +
//  GolfExportData over tournament rounds) so the profile never disagrees with
//  the app. Never snapshot into the bio blob.
//

import SwiftUI

struct RecruitingGolfStatBand: View {
    let athlete: Athlete

    var body: some View {
        // Tournament rounds only: practice scores carry no recruiting credibility,
        // so Rounds/Best/Avg all derive from the same tournament set (and
        // `tournamentAverage` is the average of exactly this set — see
        // GolfExportData.summary, so the profile agrees with the Stats screen).
        let tScores = GolfExportData.tournamentRounds(for: athlete, season: nil).compactMap { $0.score }
        let tournamentAverage = GolfExportData.summary(for: athlete, season: nil).tournamentAverage
        let advanced = GolfExportData.advancedStats(for: athlete, season: nil)
        let handicap = HandicapEstimator.estimatedIndex(for: athlete, season: nil)

        VStack(alignment: .leading, spacing: 12) {
            Text("Golf")
                .font(.headingMedium)

            if tScores.isEmpty {
                emptyState
            } else {
                grid(leadChips(scores: tScores, average: tournamentAverage, handicap: handicap))
                if advanced.hasDetailed {
                    grid(detailedChips(advanced))
                }
                Text("Scoring (avg / best / rounds) from tournament rounds only.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func grid(_ chips: [CompactStatData]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                CompactStatChip(data: chip)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.golf")
                .foregroundStyle(.secondary)
            Text("Play a scored tournament round to show your scoring stats.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    // MARK: - Chip builders (mirror GolfStatsSection so values agree)

    private func leadChips(scores: [Int], average: Double?, handicap: Double?) -> [CompactStatData] {
        var chips: [CompactStatData] = []
        if let handicap {
            chips.append(.init(label: "Est. Handicap", value: handicapString(handicap), color: Theme.golfAccent))
        }
        if let average {
            chips.append(.init(label: "Round Avg", value: String(format: "%.1f", average), color: .brandNavy))
        }
        if let best = scores.min() {
            chips.append(.init(label: "Best", value: "\(best)", color: .green))
        }
        chips.append(.init(label: "Rounds", value: "\(scores.count)", color: .secondary))
        return chips
    }

    private func detailedChips(_ s: GolfAdvancedStats) -> [CompactStatData] {
        var chips: [CompactStatData] = []
        if let g = s.girPct { chips.append(.init(label: "GIR", value: pctString(g), color: .green)) }
        if let f = s.firPct { chips.append(.init(label: "Fairways", value: pctString(f), color: .brandNavy)) }
        if let p = s.puttsPerRound { chips.append(.init(label: "Putts / Rnd", value: oneDecimal(p), color: .brandNavy)) }
        if let sc = s.scramblingPct { chips.append(.init(label: "Scrambling", value: pctString(sc), color: .mint)) }
        return chips
    }

    // MARK: - Formatting (matches GolfStatsSection)

    private func handicapString(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r < 0 ? "+\(String(format: "%.1f", -r))" : String(format: "%.1f", r)
    }

    private func pctString(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }
}
