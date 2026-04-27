//
//  PhotoTagSheet.swift
//  PlayerPath
//
//  Sheet to tag a photo to a game or practice.
//

import SwiftUI
import SwiftData

struct PhotoTagSheet: View {
    @Bindable var photo: Photo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Query games and practices for the photo's athlete only
    @Query private var games: [Game]
    @Query private var practices: [Practice]

    init(photo: Photo) {
        self.photo = photo
        let id = photo.athlete?.id
        if let id {
            self._games = Query(
                filter: #Predicate<Game> { $0.athlete?.id == id },
                sort: [SortDescriptor(\Game.date, order: .reverse)]
            )
            self._practices = Query(
                filter: #Predicate<Practice> { $0.athlete?.id == id },
                sort: [SortDescriptor(\Practice.date, order: .reverse)]
            )
        } else {
            self._games = Query(sort: [SortDescriptor(\Game.date, order: .reverse)])
            self._practices = Query(sort: [SortDescriptor(\Practice.date, order: .reverse)])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Games") {
                    Button {
                        photo.game = nil
                        save()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundColor(.primary)
                            Spacer()
                            if photo.game == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }

                    ForEach(games) { game in
                        Button {
                            photo.game = game
                            photo.practice = nil
                            // Keep the photo's season aligned with the game it
                            // was just tagged to — otherwise the photo stays on
                            // its import-time season (often the wrong one for
                            // old photos). Only overwrite when the game has a
                            // season; don't clobber on orphaned games.
                            if let gameSeason = game.season {
                                photo.season = gameSeason
                            }
                            save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("vs \(game.opponent)")
                                        .foregroundColor(.primary)
                                    if let date = game.date {
                                        Text(date, style: .date)
                                            .font(.bodySmall)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if photo.game?.id == game.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.brandNavy)
                                }
                            }
                        }
                    }
                }

                Section("Practices") {
                    Button {
                        photo.practice = nil
                        save()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundColor(.primary)
                            Spacer()
                            if photo.practice == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }

                    ForEach(practices) { practice in
                        Button {
                            photo.practice = practice
                            photo.game = nil
                            if let practiceSeason = practice.season {
                                photo.season = practiceSeason
                            }
                            save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Practice")
                                        .foregroundColor(.primary)
                                    if let date = practice.date {
                                        Text(date, style: .date)
                                            .font(.bodySmall)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if photo.practice?.id == practice.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.brandNavy)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tag Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        photo.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoTagSheet.save")
        dismiss()
    }
}
