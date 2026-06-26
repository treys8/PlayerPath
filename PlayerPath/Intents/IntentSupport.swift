//
//  IntentSupport.swift
//  PlayerPath
//
//  Read-only @MainActor bridge that App Intents use to reach the shared
//  SwiftData container without an @Environment(\.modelContext). App Intents
//  run in the app's own process, so `mainContext` is the same store the UI
//  reads. Several getters return @Model values (Athlete) for synchronous,
//  same-tick use on the main actor — CALLERS must snapshot any needed fields
//  to value types (UUID/String) BEFORE the next `await`, never holding a
//  @Model across a suspension (mirrors GameService.deleteGameDeep's discipline).
//

import Foundation
import SwiftData

@MainActor
enum IntentSupport {
    /// The app's single shared container's main context.
    static var context: ModelContext { PlayerPathApp.sharedModelContainer.mainContext }

    /// The signed-in user (single account per device). Prefer the row that has a
    /// Firebase Auth UID; fall back to the only row if present.
    static func currentUser() -> User? {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        return users.first(where: { $0.firebaseAuthUid != nil }) ?? users.first
    }

    /// Every athlete profile for the signed-in user.
    static func allAthletes() -> [Athlete] {
        if let athletes = currentUser()?.athletes, !athletes.isEmpty {
            return athletes
        }
        return (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
    }

    static func athletes(withIDs ids: [UUID]) -> [Athlete] {
        let wanted = Set(ids)
        return allAthletes().filter { wanted.contains($0.id) }
    }

    /// The profile currently selected in-app, mirroring UserMainFlow's
    /// `lastSelectedAthleteID_<userID>` UserDefaults persistence. Falls back to
    /// the first profile.
    static func resolveActiveAthlete() -> Athlete? {
        let athletes = allAthletes()
        // Prefer the User row that actually has a remembered selection — that's
        // the signed-in user even when a stale same-email row also carries a
        // firebaseAuthUid (see AuthenticatedFlow's stale-row handling). Keying
        // off `currentUser()` alone could pick the wrong row on such devices.
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        for user in users {
            let key = "lastSelectedAthleteID_\(user.id.uuidString)"
            if let saved = UserDefaults.standard.string(forKey: key),
               let uuid = UUID(uuidString: saved),
               let match = athletes.first(where: { $0.id == uuid }) {
                return match
            }
        }
        return athletes.first
    }

    /// Profiles linked to the same human (shared personGroupID, falling back to
    /// `id` for ungrouped singletons). A two-sport person returns ≥2 here.
    static func siblingProfiles(of athlete: Athlete) -> [Athlete] {
        let group = athlete.personGroupID ?? athlete.id
        return allAthletes().filter { ($0.personGroupID ?? $0.id) == group }
    }
}
