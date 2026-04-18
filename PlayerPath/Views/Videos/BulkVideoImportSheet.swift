//
//  BulkVideoImportSheet.swift
//  PlayerPath
//
//  Modal progress UI for bulk-importing videos from the Photos library.
//  Owns a BulkVideoImportViewModel and dismisses on completion via the
//  onComplete callback so the parent can surface a result toast.
//

import SwiftUI
import SwiftData
import PhotosUI

struct BulkVideoImportSheet: View {
    let items: [PhotosPickerItem]
    let athlete: Athlete
    var game: Game? = nil
    var practice: Practice? = nil
    /// When set by the caller (e.g., an upload button inside a specific
    /// season's detail view), the user has already chosen the target season
    /// so confirmation is skipped and every clip is routed to this season.
    var preselectedSeason: Season? = nil
    let onComplete: (_ succeeded: Int, _ failed: Int, _ stoppedForQuota: Bool, _ wasCancelled: Bool) -> Void

    @State private var viewModel = BulkVideoImportViewModel()
    @State private var hasStarted = false
    @State private var seasonOverride: Season?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Confirmation appears only when the user has multiple seasons AND the
    /// parent didn't pre-pin a game/practice/season. In every other case,
    /// import starts instantly (legacy behavior).
    private var shouldConfirm: Bool {
        preselectedSeason == nil &&
        game == nil && practice == nil &&
        (athlete.seasons?.count ?? 0) > 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasStarted && shouldConfirm {
                    confirmationView
                } else {
                    importingView
                }
            }
            .interactiveDismissDisabled()
            .task {
                guard !shouldConfirm else { return }
                await startImport()
            }
        }
    }

    private var confirmationView: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brandNavy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Import")
                            .font(.headline)
                        Text("^[\(items.count) video](inflect: true) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                SeasonPickerRow(
                    athlete: athlete,
                    selection: $seasonOverride,
                    allowsNone: true,
                    noneLabel: "Match by date (recommended)"
                )
            } header: {
                Text("Season")
            } footer: {
                if seasonOverride == nil {
                    Text("Each video is placed on the season that contains its capture date. Pick a specific season to override.")
                } else {
                    Text("All imported videos will be placed on this season, regardless of capture date.")
                }
            }

            Section {
                Button {
                    Task { await startImport() }
                } label: {
                    Text("Start Import")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandNavy)

                Button(role: .cancel) {
                    onComplete(0, 0, false, true)
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Import Videos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var importingView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brandNavy)

            Text("Importing Videos")
                .font(.title2)
                .fontWeight(.bold)

            if case .importing(let current, let total) = viewModel.status {
                VStack(spacing: 12) {
                    ProgressView(value: Double(current), total: Double(total))
                        .tint(.brandNavy)
                        .padding(.horizontal, 40)
                    Text("\(current) of \(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            if case .importing = viewModel.status {
                Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
    }

    private func startImport() async {
        hasStarted = true
        await viewModel.runImport(
            items: items,
            athlete: athlete,
            modelContext: modelContext,
            game: game,
            practice: practice,
            seasonOverride: seasonOverride ?? preselectedSeason
        )
        if case .completed(let succeeded, let failed, let quota, let cancelled) = viewModel.status {
            onComplete(succeeded, failed, quota, cancelled)
            dismiss()
        }
    }
}
