//
//  SplitSportProfileSheet.swift
//  PlayerPath
//
//  Opt-in migration UI for a LEGACY single-row multi-sport athlete — a row that
//  tracks 2+ sports' seasons at once (the old "Add a sport" model). Splitting moves
//  each non-primary sport's data onto its own `personGroupID`-linked profile so the
//  person reads as one athlete with switchable sports, can run overlapping seasons,
//  and keeps per-sport stats separate — without using an extra subscription slot.
//
//  The heavy lifting lives in SportProfileSplitService. This sheet shows a dry-run
//  preview, refuses unsafe states (offline / in-flight uploads / coach-shared), and
//  confirms before committing. The original row stays selected afterward.
//

import SwiftUI
import SwiftData

struct SplitSportProfileSheet: View {
    @Bindable var athlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent

    @State private var showingConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var previews: [SportProfileSplitService.MovePreview] {
        SportProfileSplitService.previews(for: athlete)
    }

    private var primarySport: Season.SportType {
        SportProfileSplitService.primarySport(for: athlete)
    }

    // MARK: - Guards

    private enum Block {
        case coachShared, uploads, offline

        var message: String {
            switch self {
            case .coachShared:
                return "This athlete is shared with a coach. Remove coach sharing before splitting — shared profiles aren't supported yet."
            case .uploads:
                return "Some videos are still uploading. Wait for uploads to finish, then try again."
            case .offline:
                return "You're offline. Splitting needs a connection so the change reaches your other devices."
            }
        }
    }

    /// Splitting a coach-shared athlete would orphan the coach's folder scope and
    /// stale its billing key — out of scope for v1, so refuse outright.
    private var isCoachShared: Bool {
        !(athlete.coaches ?? []).isEmpty
    }

    /// Re-keying a clip mid-upload races the queue (the in-flight write would land
    /// the OLD athleteId, and cancel-by-athlete wouldn't match). Refuse while any of
    /// this row's clips are active or pending.
    private var hasInFlightUploads: Bool {
        let manager = UploadQueueManager.shared
        let clipIDs = Set((athlete.videoClips ?? []).map(\.id))
        if manager.pendingUploads.contains(where: { $0.athleteId == athlete.id }) { return true }
        if manager.pendingUploads.contains(where: { clipIDs.contains($0.clipId) }) { return true }
        return clipIDs.contains { manager.activeUploads[$0] != nil }
    }

    private var block: Block? {
        if isCoachShared { return .coachShared }
        if hasInFlightUploads { return .uploads }
        if !ConnectivityMonitor.shared.isConnected { return .offline }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("This profile tracks more than one sport. Splitting gives each sport its own profile so you can keep separate seasons and stats and run them at the same time. It uses no extra subscription slot.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                primaryRow

                VStack(spacing: 10) {
                    ForEach(previews) { previewCard($0) }
                }
                .padding(.horizontal, 20)

                if let block {
                    Label(block.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.labelMedium)
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.warning.opacity(0.12)))
                        .padding(.horizontal, 20)
                }

                Text("This can't be undone automatically.")
                    .font(.labelSmall)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Split Sports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Split") { showingConfirmation = true }
                    .fontWeight(.semibold)
                    .disabled(block != nil || previews.isEmpty)
            }
        }
        .confirmationDialog(
            "Split \(athlete.name) into separate sport profiles?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Split Profiles") { performSplit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates \(previews.count) new linked profile\(previews.count == 1 ? "" : "s") and moves each sport's seasons, games, videos, and photos. Your \(primarySport.displayName) data stays here. This can't be undone automatically.")
        }
        .alert("Unable to Split", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var primaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: primarySport.icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundColor(Theme.accent(forGolf: primarySport == .golf))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(primarySport.displayName) stays here")
                    .font(.bodyLarge)
                    .foregroundColor(.primary)
                Text("This profile keeps its \(primarySport.displayName) seasons and stats.")
                    .font(.labelSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        .padding(.horizontal, 20)
    }

    private func previewCard(_ preview: SportProfileSplitService.MovePreview) -> some View {
        HStack(spacing: 12) {
            Image(systemName: preview.sport.icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundColor(Theme.accent(forGolf: preview.sport == .golf))
            VStack(alignment: .leading, spacing: 2) {
                Text("New \(preview.sport.displayName) profile")
                    .font(.bodyLarge)
                    .foregroundColor(.primary)
                Text(movesSummary(preview))
                    .font(.labelSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accent(forGolf: preview.sport == .golf).opacity(0.08))
        )
    }

    private func movesSummary(_ preview: SportProfileSplitService.MovePreview) -> String {
        var parts: [String] = []
        func add(_ count: Int, _ singular: String, _ plural: String) {
            guard count > 0 else { return }
            parts.append("\(count) \(count == 1 ? singular : plural)")
        }
        add(preview.seasons, "season", "seasons")
        add(preview.games, "game", "games")
        add(preview.videos, "video", "videos")
        add(preview.photos, "photo", "photos")
        return parts.isEmpty ? "Moves this sport to its own profile" : "Moves " + parts.joined(separator: ", ")
    }

    // MARK: - Action

    private func performSplit() {
        guard block == nil else { Haptics.warning(); return }
        do {
            let newRows = try SportProfileSplitService.split(athlete: athlete, in: modelContext)
            guard !newRows.isEmpty else { dismiss(); return }

            // Propagate: syncAll syncs Athletes FIRST, so each new row gets a firestoreId
            // before its moved children upload (children skip until the parent has synced).
            if let user = athlete.user {
                Task { try? await SyncCoordinator.shared.syncAll(for: user) }
            }

            // The original row (still selected) sheds the moved sports in place — no
            // athlete switch, matching "keep my main profile, peel off the other sport."
            Haptics.success()
            dismiss()
        } catch {
            // The service rolled back on save failure, so nothing changed — surface a
            // clean error and stay on the sheet rather than syncing a ghost move.
            Haptics.error()
            ErrorHandlerService.shared.reportError(
                error,
                context: "SplitSportProfileSheet.split",
                message: $errorMessage,
                isPresented: $showingError,
                userMessage: "Couldn't move that sport to its own profile. Nothing was changed — please try again."
            )
        }
    }
}
