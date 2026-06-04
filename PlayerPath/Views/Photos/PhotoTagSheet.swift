//
//  PhotoTagSheet.swift
//  PlayerPath
//
//  Sheet to tag a single photo to a game/round or practice. Wraps the shared
//  EventTargetPicker (golf rounds grouped under their tournaments) and applies
//  the choice to the bound photo.
//

import SwiftUI
import SwiftData

struct PhotoTagSheet: View {
    @Bindable var photo: Photo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if let athlete = photo.athlete {
                    EventTargetPicker(
                        athlete: athlete,
                        selectedGameID: photo.game?.id,
                        selectedPracticeID: photo.practice?.id,
                        showsSelection: true,
                        onSelect: apply
                    )
                } else {
                    ContentUnavailableView("No Athlete", systemImage: "person.slash")
                }
            }
            .ppDetailBackground()
            .navigationTitle("Tag Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func apply(_ target: EventTargetPicker.Target) {
        switch target {
        case .game(let game):
            photo.game = game
            photo.practice = nil
            // Keep the photo's season aligned with the event it was just tagged
            // to — but only when the event has a season, so we don't blank out
            // the photo's season on an orphaned game/round.
            if let season = game.season { photo.season = season }
        case .practice(let practice):
            photo.practice = practice
            photo.game = nil
            if let season = practice.season { photo.season = season }
        case .clear:
            photo.game = nil
            photo.practice = nil
        }
        photo.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoTagSheet.apply")
        dismiss()
    }
}
