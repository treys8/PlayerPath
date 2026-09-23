//
//  ShareClipToFolderPicker.swift
//  PlayerPath
//
//  "Share a Clip" from inside a coach folder: pick one of this athlete's library
//  clips, then hand off to ShareToCoachFolderView with the folder preselected.
//
//  Replaces the folder menu's old route into CoachVideoUploadView — the COACH
//  upload queue — which stamped the athlete's clip as a coach-authored private
//  draft that no coach could see. Sharing from the library also keeps the clip
//  linked to its folder copy (VideoClip.sharedCoachVideoIDs), so the coach's
//  feedback reaches the Journal and the clip's own player.
//

import SwiftUI
import SwiftData

struct ShareClipToFolderPicker: View {
    let folder: SharedFolder

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var clips: [VideoClip]
    @State private var clipToShare: VideoClip?

    init(folder: SharedFolder) {
        self.folder = folder
        // Scope to the folder's athlete. Legacy folders (no athleteUUID) accept
        // any of the account's athletes, matching ShareToCoachFolderView.
        if let uuidString = folder.athleteUUID, let athleteID = UUID(uuidString: uuidString) {
            _clips = Query(
                filter: #Predicate<VideoClip> { $0.athlete?.id == athleteID },
                sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
            )
        } else {
            _clips = Query(sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)])
        }
    }

    private var visibleClips: [VideoClip] {
        clips.filter { !$0.isDeletedRemotely }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleClips.isEmpty {
                    ContentUnavailableView(
                        "No Clips Yet",
                        systemImage: "video.slash",
                        description: Text("Record or import a clip, then come back to share it with your coach.")
                    )
                } else {
                    List(visibleClips) { clip in
                        // Sharing uploads the local file, so a cloud-only clip
                        // can't be shared from here — say so up front instead of
                        // failing after the tap.
                        let isLocal = FileManager.default.fileExists(atPath: clip.resolvedFilePath)
                        Button { clipToShare = clip } label: { row(clip, isLocal: isLocal) }
                            .buttonStyle(.plain)
                            .disabled(!isLocal)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Share a Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $clipToShare) { clip in
                ShareToCoachFolderView(
                    clip: clip,
                    preselectedFolderID: folder.id,
                    onShared: { dismiss() }
                )
                .environmentObject(authManager)
            }
        }
        .tint(ppAccent)
    }

    private func row(_ clip: VideoClip, isLocal: Bool) -> some View {
        HStack(spacing: 12) {
            VideoThumbnailView(
                clip: clip,
                size: CGSize(width: 72, height: 40),
                cornerRadius: 8,
                showPlayResult: false,
                showHighlight: false,
                showSeason: false,
                showContext: false,
                showDuration: true,
                fillsContainer: false
            )
            .frame(width: 72, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: clip))
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text(isLocal ? subtitle(for: clip) : "Not on this device — open it to download first")
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if clip.isHighlight {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(ppAccent)
                    .accessibilityLabel("Highlight")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .opacity(isLocal ? 1 : 0.5)
    }

    private func title(for clip: VideoClip) -> String {
        clip.displayTagName ?? (clip.isHighlight ? "Highlight" : "Clip")
    }

    /// Where the clip came from, then when — "vs Tigers · Sep 3, 2026".
    private func subtitle(for clip: VideoClip) -> String {
        var parts: [String] = []
        if let game = clip.game {
            parts.append(game.opponentLabel)
        } else if clip.practice != nil {
            parts.append("Practice")
        }
        if let date = clip.createdAt {
            parts.append(DateFormatter.mediumDate.string(from: date))
        }
        return parts.isEmpty ? "Clip" : parts.joined(separator: " · ")
    }
}
