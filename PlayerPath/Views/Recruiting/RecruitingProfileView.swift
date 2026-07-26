//
//  RecruitingProfileView.swift
//  PlayerPath
//
//  In-app preview of the recruiting profile — mirrors what a college coach sees
//  on the public web page. Video-first: highlights lead; golf gets the full
//  derived stat band, baseball/softball get opt-in measurables. PII shows only
//  when its per-field toggle is on.
//
//  Every string here comes from RecruitingInfo's display helpers or
//  RecruitingGolfStats — the same sources RecruitingProfileService serializes at
//  publish — so this preview and the published page can't disagree.
//
//  `info` carries the bio (so the editor can preview unsaved edits); `athlete`
//  supplies the highlight clips and live golf stats.
//

import SwiftUI

struct RecruitingProfileView: View {
    let athlete: Athlete
    let info: RecruitingInfo
    /// The clips actually on the published page, in page order. Nil previews the
    /// newest highlights — correct only before a first publish, which is why the
    /// publish screen always passes its live selection.
    var curatedClipIDs: [UUID]?

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                card { RecruitingHighlightStrip(athlete: athlete, curatedClipIDs: curatedClipIDs) }

                if isGolf {
                    card { RecruitingGolfStatBand(athlete: athlete) }
                } else if !info.measurableItems.isEmpty {
                    card { measurablesBand }
                }

                if !info.visibleContactItems.isEmpty {
                    card { contactBand }
                }

                if let bio = info.bio, !bio.isEmpty {
                    card {
                        Text("About").font(.headingMedium)
                        Text(bio).font(.bodyMedium).foregroundColor(.primary)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .ppAccent(for: athlete.sport)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            RecruitingHeadshotImage(url: info.headshotCloudURL, size: 110)
            Text(athlete.name)
                .font(.displayMedium)
                .multilineTextAlignment(.center)
            if let subline = info.subline(sport: athlete.sport ?? .baseball) {
                Text(subline)
                    .font(.headingMedium)
                    .foregroundColor(.secondary)
            }
            if let physicalLine = info.physicalLine(isGolf: isGolf) {
                Text(physicalLine)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let schoolLine = info.schoolLine {
                Text(schoolLine)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Bands

    private var measurablesBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurables").font(.headingMedium)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(info.measurableItems, id: \.kind) { item in
                    CompactStatChip(data: .init(label: item.label, value: item.value, color: .brandNavy))
                }
            }
            Text("Self-reported by the athlete.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var contactBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contact & Academics").font(.headingMedium)
            ForEach(info.visibleContactItems, id: \.kind) { item in
                HStack {
                    Text(item.label).font(.labelMedium).foregroundColor(.secondary)
                    Spacer()
                    Text(item.value).font(.bodyMedium).foregroundColor(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Card wrapper

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }
}
