//
//  AthleteAppEntity.swift
//  PlayerPath
//
//  AppEntity wrapper for an athlete profile, used by StartGameIntent so a
//  two-sport person (baseball + golf profiles linked by personGroupID) can be
//  disambiguated ("which profile?"). The entity carries primitives only — the
//  @Model is read on the main actor at construction and never crosses an await.
//

import AppIntents
import Foundation

struct AthleteAppEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static let defaultQuery = AthleteEntityQuery()

    let id: UUID
    let name: String
    let sportLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(sportLabel)")
    }

    @MainActor
    init(_ athlete: Athlete) {
        self.id = athlete.id
        self.name = athlete.name
        self.sportLabel = (athlete.sport ?? .baseball).rawValue.capitalized
    }
}

struct AthleteEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [AthleteAppEntity.ID]) async throws -> [AthleteAppEntity] {
        IntentSupport.athletes(withIDs: identifiers).map(AthleteAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AthleteAppEntity] {
        IntentSupport.allAthletes().map(AthleteAppEntity.init)
    }
}
