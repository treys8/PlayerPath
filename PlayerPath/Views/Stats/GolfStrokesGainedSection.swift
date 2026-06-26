//
//  GolfStrokesGainedSection.swift
//  PlayerPath
//
//  Plus-gated "Est. Strokes Gained" subsection inside GolfStatsSection. Computes
//  live via ShotStrokesGained (no stored stats). Plus users see a signed SG
//  total vs the PGA Tour baseline, an SG-by-par-type split, and — when shots are
//  logged — OTT / APP / ARG category bars. Free users see a locked upsell tile
//  (not hidden) that opens the paywall, while the free ShotStats / Driving
//  sections above remain visible and ungated.
//

import SwiftUI
import SwiftData

struct GolfStrokesGainedSection: View {
    let athlete: Athlete?
    /// nil = all golf rounds; otherwise scoped to this season (matches GolfStatsSection).
    let season: Season?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingPaywall = false

    private var isUnlocked: Bool { SubscriptionGate.effectiveAthleteTier.hasStrokesGained }

    private var stats: ShotStrokesGainedStats? {
        guard let athlete else { return nil }
        return ShotStrokesGained.compute(for: athlete, season: season)
    }

    /// Tier the upsell points at (free → Plus).
    private var upsellTierName: String {
        (SubscriptionGate.effectiveAthleteTier.nextTier ?? .plus).displayName
    }

    var body: some View {
        if isUnlocked {
            unlockedContent
        } else {
            lockedTile
        }
    }

    // MARK: - Unlocked (Plus)

    @ViewBuilder
    private var unlockedContent: some View {
        // Compute once — `compute` walks every round/hole/shot, and this property
        // is read twice across the branches below.
        let computed = stats
        if let s = computed, s.hasData {
            VStack(alignment: .leading, spacing: 12) {
                header
                sgTotalCard(s)
                byParTiles(s)
                if let cat = s.sgByCategory {
                    categoryBars(cat, complete: s.completeCategorySG)
                }
                disclaimer
            }
        } else if computed != nil {
            // Plus, has golf rounds but no known hole yardages → discoverability
            // hint rather than a silent gap (SG needs yardage to compute).
            VStack(alignment: .leading, spacing: 6) {
                header
                Text("Add hole yardages (tap a hole → Yardage) to unlock Est. Strokes Gained.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Est. Strokes Gained")
                .font(.headingMedium)
            Text("vs PGA Tour baseline")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func sgTotalCard(_ s: ShotStrokesGainedStats) -> some View {
        let v = s.sgTotalPerRound ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.title2)
                .foregroundColor(Theme.golfAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("SG Total")
                    .font(.labelMedium)
                    .foregroundColor(.secondary)
                Text(signed(v))
                    .font(.ppStatLarge)
                    .monospacedDigit()
                    .foregroundColor(sgColor(v))
                Text("per round · \(s.roundCount) round\(s.roundCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.spacingMedium)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }

    private func byParTiles(_ s: ShotStrokesGainedStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Hole Type")
                .font(.labelMedium)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                sgParTile("Par 3", s.sgByPar.par3)
                sgParTile("Par 4", s.sgByPar.par4)
                sgParTile("Par 5", s.sgByPar.par5)
            }
        }
    }

    private func sgParTile(_ label: String, _ v: Double?) -> some View {
        VStack(spacing: 4) {
            Text(v.map { signed($0) } ?? "—")
                .font(.ppStatLarge)
                .monospacedDigit()
                .foregroundColor(v.map { sgColor($0) } ?? .secondary)
            Text(label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .statCardBackground()
    }

    // MARK: - Category bars (Layer 2)

    @ViewBuilder
    private func categoryBars(_ cat: (ott: Double?, app: Double?, arg: Double?), complete: Bool) -> some View {
        // Only show categories that actually computed. In v1 distance is captured
        // for approaches/par-3 tees only (not greenside, and never putts), so
        // Around-Green is usually uncomputable and Approach is sparse — showing
        // "—" rows for them on most accounts would read as broken. Off-the-Tee is
        // the reliably-covered category.
        let rows: [(label: String, value: Double?)] = [
            ("Off the Tee", cat.ott),
            ("Approach", cat.app),
            ("Around Green", cat.arg)
        ].filter { $0.value != nil }
        if !rows.isEmpty {
            let maxMag = max(0.1, rows.compactMap { $0.value.map(abs) }.max() ?? 0.1)
            VStack(alignment: .leading, spacing: 8) {
                Text("By Category")
                    .font(.labelMedium)
                    .foregroundColor(.secondary)
                ForEach(rows, id: \.label) { row in
                    categoryRow(label: row.label, value: row.value, maxMag: maxMag)
                }
                if !complete {
                    Text("Partial — approach & around-green SG aren't fully captured in v1 (no greenside or putt distances yet).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func categoryRow(label: String, value: Double?, maxMag: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.bodySmall)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                let frac = value.map { min(1, abs($0) / maxMag) } ?? 0
                Capsule()
                    .fill((value ?? 0) >= 0 ? Color.green.opacity(0.8) : Theme.warning.opacity(0.8))
                    .frame(width: max(2, geo.size.width * frac), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)
            Text(value.map { signed($0) } ?? "—")
                .font(.labelMedium)
                .monospacedDigit()
                .foregroundColor(value.map { sgColor($0) } ?? .secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var disclaimer: some View {
        Text("Estimated vs the PGA Tour baseline (Broadie). No course rating/slope; putting isn't included yet.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    // MARK: - Locked (free) upsell tile

    private var lockedTile: some View {
        Button {
            Haptics.light()
            showingPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundColor(Theme.golfAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. Strokes Gained")
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                    Text("See where you gain and lose strokes vs the PGA Tour baseline — a \(upsellTierName) feature.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.spacingMedium)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
    }

    // MARK: - Formatting

    /// Signed SG display: "+1.2" / "-2.3" / "E" near zero. Higher = better.
    private func signed(_ v: Double) -> String {
        if abs(v) < 0.05 { return "E" }
        let r = (v * 10).rounded() / 10
        return r > 0 ? "+\(String(format: "%.1f", r))" : String(format: "%.1f", r)
    }

    /// Green when strokes are gained, calm amber when lost, neutral at ~0.
    private func sgColor(_ v: Double) -> Color {
        if v > 0.05 { return .green }
        if v < -0.05 { return Theme.warning }
        return .primary
    }
}
