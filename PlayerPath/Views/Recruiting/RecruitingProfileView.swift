//
//  RecruitingProfileView.swift
//  PlayerPath
//
//  In-app preview of the recruiting profile — mirrors what a college coach will
//  see on the eventual public web page (Phase 2). Video-first: highlights lead;
//  golf gets the full derived stat band, baseball/softball get opt-in
//  measurables. PII shows only when its per-field toggle is on.
//
//  `info` carries the bio (so the editor can preview unsaved edits); `athlete`
//  supplies the highlight clips and live golf stats.
//

import SwiftUI

struct RecruitingProfileView: View {
    let athlete: Athlete
    let info: RecruitingInfo

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                card { RecruitingHighlightStrip(athlete: athlete) }

                if isGolf {
                    card { RecruitingGolfStatBand(athlete: athlete) }
                } else if info.showMeasurables && !measurableChips.isEmpty {
                    card { measurablesBand }
                }

                if hasVisibleContact {
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
            if let subline {
                Text(subline)
                    .font(.headingMedium)
                    .foregroundColor(.secondary)
            }
            if let physicalLine {
                Text(physicalLine)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let schoolLine {
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
                ForEach(Array(measurableChips.enumerated()), id: \.offset) { _, chip in
                    CompactStatChip(data: chip)
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
            if info.includeGPA, let gpa = info.gpa {
                infoRow("GPA", String(format: "%.2f", gpa))
            }
            if info.includeContactEmail, let email = info.contactEmail, !email.isEmpty {
                infoRow("Email", email)
            }
            if info.includeContactPhone, let phone = info.contactPhone, !phone.isEmpty {
                infoRow("Phone", phone)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.labelMedium).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.bodyMedium).foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Derived lines

    private var subline: String? {
        var parts: [String] = []
        if let g = info.gradYear { parts.append("Class of \(g)") }
        if !isGolf, let pos = info.primaryPosition, !pos.isEmpty { parts.append(pos) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var physicalLine: String? {
        var parts: [String] = []
        if let h = info.heightFormatted { parts.append(h) }
        if let w = info.weightLbs { parts.append("\(w) lbs") }
        if !isGolf, let bats = info.bats, let throwsHand = info.throwsHand,
           !bats.isEmpty, !throwsHand.isEmpty {
            parts.append("B/T \(bats)/\(throwsHand)")
        }
        if let loc = info.locationLine { parts.append(loc) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var schoolLine: String? {
        let parts = [info.highSchool, info.clubTeam]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var measurableChips: [CompactStatData] {
        var chips: [CompactStatData] = []
        if let v = info.sixtyYardDash {
            chips.append(.init(label: "60 Yard", value: String(format: "%.2f", v) + "s", color: .brandNavy))
        }
        if let v = info.exitVelo {
            chips.append(.init(label: "Exit Velo", value: "\(Int(v.rounded())) mph", color: .brandNavy))
        }
        if let v = info.throwingVelo {
            chips.append(.init(label: "Throw Velo", value: "\(Int(v.rounded())) mph", color: .brandNavy))
        }
        if let v = info.pitchVelo {
            chips.append(.init(label: "Pitch Velo", value: "\(Int(v.rounded())) mph", color: .brandNavy))
        }
        return chips
    }

    private var hasVisibleContact: Bool {
        (info.includeGPA && info.gpa != nil) ||
        (info.includeContactEmail && !(info.contactEmail ?? "").isEmpty) ||
        (info.includeContactPhone && !(info.contactPhone ?? "").isEmpty)
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
