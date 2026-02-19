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

    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]
    @Query(sort: \Practice.date, order: .reverse) private var allPractices: [Practice]

    private var games: [Game] {
        allGames.filter { $0.athlete?.id == photo.athlete?.id }
    }

    private var practices: [Practice] {
        allPractices.filter { $0.athlete?.id == photo.athlete?.id }
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
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    ForEach(games) { game in
                        Button {
                            photo.game = game
                            photo.practice = nil
                            save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("vs \(game.opponent)")
                                        .foregroundColor(.primary)
                                    if let date = game.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if photo.game?.id == game.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
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
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    ForEach(practices) { practice in
                        Button {
                            photo.practice = practice
                            photo.game = nil
                            save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Practice")
                                        .foregroundColor(.primary)
                                    if let date = practice.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if photo.practice?.id == practice.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
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
        try? modelContext.save()
        dismiss()
    }
}
