//
//  AthletePersonGroup.swift
//  PlayerPath
//
//  Collapses sport-variant Athlete profiles (linked by `personGroupID`) into
//  one entry per human for the athlete picker, plus the grid card that renders
//  a multi-sport person with an inline sport switcher. A single profile — even
//  a legacy row that tracks several sports — stays a normal `AthleteCard`.
//

import SwiftUI
import SwiftData

// MARK: - Grouping

/// A single human represented by one or more sport-variant `Athlete` profiles
/// linked by `personGroupID`. The picker shows one entry per person and, for
/// multi-sport people, an inline sport switcher so two linked profiles read as
/// one athlete.
struct AthletePersonGroup: Identifiable {
    /// Shared `personGroupID`, or the lone profile's `id` for ungrouped singletons.
    let id: UUID
    /// Member profiles, one per sport, sorted by sport for stable ordering.
    let profiles: [Athlete]

    /// Display name for the person. Linked profiles normally share a name; falls
    /// back to the first profile if a spin-off was given a different name.
    var displayName: String { profiles.first?.name ?? "" }

    /// True only when the person has more than one linked sport profile — the
    /// single case that needs an in-card sport switcher. A legacy single row
    /// that tracks multiple sports stays a singleton (nothing to switch to).
    var isMultiSport: Bool { profiles.count > 1 }
}

extension Array where Element == Athlete {
    /// Collapse sport-variant profiles into one entry per person, keyed by
    /// `personGroupID ?? id`. Groups are sorted by name (then id for stability);
    /// each group's profiles are sorted by sport.
    func groupedByPerson() -> [AthletePersonGroup] {
        Dictionary(grouping: self) { $0.personGroupID ?? $0.id }
            .map { key, members in
                AthletePersonGroup(
                    id: key,
                    profiles: members.sorted { $0.sportType.rawValue < $1.sportType.rawValue }
                )
            }
            .sorted {
                let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                if order == .orderedSame { return $0.id.uuidString < $1.id.uuidString }
                return order == .orderedAscending
            }
    }
}

// MARK: - Multi-sport person card

/// Athlete-picker card for a person with multiple linked sport profiles. Shows
/// the name once and a row of sport chips; tapping a chip opens that profile.
/// Single-profile people use `AthleteCard` instead.
struct MultiSportPersonCard: View {
    let group: AthletePersonGroup
    /// Opens the given sport profile (the presenter sets it active + dismisses).
    let onSelect: (Athlete) -> Void
    /// Optional spin-off action — shown only when the person can still add a
    /// sport. The presenter owns the resulting sheet.
    var onAddSport: (() -> Void)? = nil

    private var canAddSport: Bool {
        group.profiles.first?.canAddSportProfile ?? false
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.brandNavy.opacity(0.8), Color.brandNavy],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }

            Text(group.displayName)
                .font(.headingLarge)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)

            VStack(spacing: 8) {
                ForEach(group.profiles) { profile in
                    Button {
                        onSelect(profile)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: profile.sportType.icon)
                                .frame(width: 20)
                            Text(profile.sportType.displayName)
                                .font(.bodyMedium)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                        .foregroundColor(.brandNavy)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(group.displayName), \(profile.sportType.displayName)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .appCard(cornerRadius: .cornerXLarge)
        .contextMenu {
            ForEach(group.profiles) { profile in
                Button {
                    onSelect(profile)
                } label: {
                    Label("Open \(profile.sportType.displayName)", systemImage: profile.sportType.icon)
                }
            }
            if let onAddSport, canAddSport {
                Divider()
                Button {
                    onAddSport()
                } label: {
                    Label("Add Another Sport", systemImage: "plus.circle")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.displayName), \(group.profiles.count) sports")
    }
}
