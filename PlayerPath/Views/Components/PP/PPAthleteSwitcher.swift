//
//  PPAthleteSwitcher.swift
//  PlayerPath
//
//  Visual overhaul — the header athlete selector.
//  A nav-bar control showing the active athlete's avatar + name + chevron. Tapping
//  opens a menu of the person's sport profiles (Baseball/Golf for a linked
//  multi-sport person group) and your other athletes, plus a "Manage Athletes…"
//  escape hatch to the full-screen selector. Switching posts `.switchAthlete`,
//  which MainTabView observes to reswap every tab's data. Distinct from the
//  account/profile entry (which lives in the More tab). Reads existing athlete
//  data only — no new fields.
//

import SwiftUI
import TipKit

struct PPAthleteSwitcher: View {
    let athlete: Athlete

    @Environment(\.ppAccent) private var ppAccent

    /// "Switch athletes" onboarding hint. Stored (not inline) so the profile
    /// buttons can `.invalidate` it once the user actually switches.
    private let athletePickerTip = AthletePickerTip()

    /// The user's full roster (same source AthleteSelectionView reads).
    private var roster: [Athlete] {
        athlete.user?.athletes ?? [athlete]
    }

    /// Group key linking sport-variant profiles of one person. Falls back to the
    /// athlete's own id so nil-grouped profiles behave like singletons.
    private func groupID(_ a: Athlete) -> UUID { a.personGroupID ?? a.id }

    /// Display name of an athlete's sport (split out to keep the sort closures
    /// fast for the type-checker).
    private func sportName(_ a: Athlete) -> String {
        (a.sport ?? .baseball).displayName
    }

    /// The active person's profiles (self + any linked sport variants).
    private var sportProfiles: [Athlete] {
        let g = groupID(athlete)
        return roster
            .filter { groupID($0) == g }
            .sorted { sportName($0) < sportName($1) }
    }

    /// Every profile belonging to a *different* person, name-sorted.
    private var otherProfiles: [Athlete] {
        let g = groupID(athlete)
        return roster
            .filter { groupID($0) != g }
            .sorted { lhs, rhs in
                lhs.name == rhs.name ? sportName(lhs) < sportName(rhs) : lhs.name < rhs.name
            }
    }

    var body: some View {
        Menu {
            ForEach(sportProfiles) { profileButton($0) }

            if !otherProfiles.isEmpty {
                Section("Other Athletes") {
                    ForEach(otherProfiles) { profileButton($0) }
                }
            }

            Divider()
            Button {
                NotificationCenter.default.post(name: .showAthleteSelection, object: nil)
                Haptics.light()
            } label: {
                Label("Manage Athletes…", systemImage: "person.2.crop.square.stack.fill")
            }
        } label: {
            switcherLabel
        }
        .accessibilityLabel("Active athlete: \(athlete.name)")
        .accessibilityHint("Switch athlete or sport profile")
        // Only hint when there's more than one profile to switch between.
        .onboardingTip(athletePickerTip, arrowEdge: .top, also: roster.count > 1)
    }

    @ViewBuilder
    private func profileButton(_ profile: Athlete) -> some View {
        let isActive = profile.id == athlete.id
        Button {
            guard !isActive else { return }
            NotificationCenter.default.post(name: .switchAthlete, object: profile)
            athletePickerTip.invalidate(reason: .actionPerformed)
        } label: {
            Label(rowTitle(profile),
                  systemImage: isActive ? "checkmark" : (profile.sport ?? .baseball).icon)
        }
    }

    /// Append the sport only when the person has more than one profile, so a
    /// single-sport athlete reads as just their name.
    private func rowTitle(_ profile: Athlete) -> String {
        let siblings = roster.filter { groupID($0) == groupID(profile) }.count
        return siblings > 1
            ? "\(profile.name) · \((profile.sport ?? .baseball).displayName)"
            : profile.name
    }

    private var switcherLabel: some View {
        HStack(spacing: 6) {
            avatar
            Text(athlete.name)
                .font(.headingMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var avatar: some View {
        AthleteHeadshotView(athlete: athlete, size: 26) {
            Circle()
                .fill(ppAccent.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay(
                    Text(initials)
                        .font(.labelMedium)
                        .foregroundStyle(ppAccent)
                )
        }
    }

    private var initials: String {
        let letters = athlete.name.split(separator: " ").prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
