//
//  ComparisonComponents.swift
//  PlayerPath
//
//  Sport-agnostic building blocks shared by the season-comparison views.
//  Extracted so the golf comparison reuses the same Plus paywall placeholder
//  and trend-chart styling as the baseball one instead of duplicating them.
//

import SwiftUI
import Charts

// MARK: - Trend chart

/// One labelled point on a metric trend line. `order` drives both the x-axis
/// sort and Identifiable so two seasons sharing a display name can't collide.
struct TrendPoint: Identifiable {
    let order: Int
    let label: String
    let value: Double
    var id: Int { order }
}

/// A single-metric line+point trend with a value-card row beneath it. The
/// caller pre-computes the points, so this view carries no sport knowledge —
/// golf feeds scoring averages, baseball could feed rate stats, etc.
struct MetricTrendChart: View {
    let title: String
    let points: [TrendPoint]
    let format: (Double) -> String
    var accent: Color = .brandNavy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headingLarge)

            if points.isEmpty {
                Text("No data available")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Season", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Season", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) trend across \(points.count) seasons, from \(points.first?.label ?? "") to \(points.last?.label ?? "")")
                .frame(height: 200)
                .chartYScale(domain: .automatic(includesZero: false))

                HStack(spacing: 12) {
                    ForEach(points) { point in
                        VStack(spacing: 4) {
                            Text(point.label)
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(format(point.value))
                                .font(.ppStatMedium)
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .statCardBackground()
    }
}

// MARK: - Plus entitlement placeholder

/// Full-screen Plus paywall shown when a gated comparison is reached without
/// the entitlement (deep link, stale navigation, or a mid-session downgrade).
struct LockedFeaturePlaceholder: View {
    let message: String
    @State private var showingPaywall = false
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text("Plus Feature")
                .font(.displayMedium)
            Text(message)
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("View Plans") { showingPaywall = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user)
            }
        }
    }
}
