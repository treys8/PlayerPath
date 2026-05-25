//
//  SportTogglePicker.swift
//  PlayerPath
//
//  Sport context switcher for multi-sport athletes. Appears above the tab bar
//  only when an athlete has seasons in more than one sport.
//

import SwiftUI

struct SportTogglePicker: View {
    @Binding var activeSport: Season.SportType
    let availableSports: [Season.SportType]

    var body: some View {
        Picker("Sport", selection: $activeSport) {
            ForEach(availableSports, id: \.self) { sport in
                Label(sport.displayName, systemImage: sport.icon)
                    .tag(sport)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Active sport")
        .accessibilityHint("Switches the tab bar between this athlete's sports")
    }
}

// MARK: - Environment

private struct ActiveSportKey: EnvironmentKey {
    static let defaultValue: Season.SportType = .baseball
}

extension EnvironmentValues {
    /// The sport context the user is currently viewing. Defaults to baseball.
    /// Set by `MainTabView` based on the athlete's seasons + their last toggle.
    var activeSport: Season.SportType {
        get { self[ActiveSportKey.self] }
        set { self[ActiveSportKey.self] = newValue }
    }
}

// MARK: - Persistence helper

enum ActiveSportStore {
    private static func key(for athleteID: UUID) -> String {
        "activeSport.\(athleteID.uuidString)"
    }

    static func load(for athleteID: UUID) -> Season.SportType? {
        guard let raw = UserDefaults.standard.string(forKey: key(for: athleteID)) else {
            return nil
        }
        return Season.SportType(rawValue: raw)
    }

    static func save(_ sport: Season.SportType, for athleteID: UUID) {
        UserDefaults.standard.set(sport.rawValue, forKey: key(for: athleteID))
    }

    /// Resolve the initial active sport for an athlete: persisted choice if valid
    /// for the current available sports, otherwise the most recent season's sport,
    /// otherwise the athlete's primary sport hint, otherwise baseball.
    static func resolve(for athlete: Athlete, available: [Season.SportType]) -> Season.SportType {
        if let saved = load(for: athlete.id), available.contains(saved) {
            return saved
        }
        let seasons = (athlete.seasons ?? []).sorted {
            ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast)
        }
        if let mostRecent = seasons.first?.sport, available.contains(mostRecent) {
            return mostRecent
        }
        if let primary = Season.SportType(rawValue: (athlete.sport ?? .baseball).rawValue.capitalized) {
            return primary
        }
        return .baseball
    }
}
