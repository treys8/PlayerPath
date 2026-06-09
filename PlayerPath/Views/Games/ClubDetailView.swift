//
//  ClubDetailView.swift
//  PlayerPath
//
//  Per-club clip review for a golf range session. A "film every swing" range
//  session can carry 100+ clips; grouping them by club behind PracticeDetailView
//  keeps each club's swings browsable instead of one endless list. Mirrors
//  HoleDetailView (the practice-round equivalent) minus the per-hole score —
//  range sessions have no holes.
//
//  `club == nil` is the "Untagged" bucket for clips saved without a club tag.
//

import SwiftUI
import SwiftData

struct ClubDetailView: View {
    let practice: Practice
    /// The club this view scopes to. `nil` = the Untagged bucket.
    let club: Club?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingReel = false
    @State private var showingReelPaywall = false
    @State private var showingBatchEditor = false

    /// True when this is the Untagged bucket (clips with no club) — where the
    /// batch club editor is offered.
    private var isUntaggedBucket: Bool { club == nil }

    /// Clips for this club (or untagged), newest first for the list.
    private var clips: [VideoClip] {
        (practice.videoClips ?? [])
            .filter { $0.club == club }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Clips in chronological (playback) order for the reel.
    private var reelClips: [VideoClip] {
        clips.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private var reelEligible: Bool { reelClips.count >= 2 }

    private var navTitle: String {
        club?.displayName ?? "Untagged"
    }

    private var sessionLabel: String {
        let course = practice.course?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (course?.isEmpty == false) ? course! : "Range Session"
    }

    private var reelTitle: String {
        "\(sessionLabel) · \(navTitle)"
    }

    /// Cache scope distinct from the round/hole reels so a club reel doesn't
    /// collide in StitchedReelCache.
    private var reelScopeKey: String {
        "club_\(practice.id.uuidString)_\(club?.rawValue ?? "none")"
    }

    var body: some View {
        List {
            Section(header: Text("Clips (\(clips.count))").smallCapsLabel()) {
                if clips.isEmpty {
                    Text(isUntaggedBucket ? "No untagged clips." : "No clips for this club.")
                        .font(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    if isUntaggedBucket {
                        Button(action: { showingBatchEditor = true }) {
                            Label("Assign club to clips", systemImage: "figure.golf")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                    if reelEligible {
                        Button(action: { generateReelTapped() }) {
                            Label("Generate Highlight Reel", systemImage: "film.stack")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                    ForEach(clips) { clip in
                        VideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess)
                    }
                }
            }
        }
        .ppDetailBackground()
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(clips: reelClips, scopeKey: reelScopeKey, title: reelTitle)
        }
        .sheet(isPresented: $showingReelPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
        .sheet(isPresented: $showingBatchEditor) {
            BatchClipTagEditor(clips: clips, mode: .club)
        }
    }

    /// Plus-gated: open the generator, or route free users to the paywall.
    private func generateReelTapped() {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            showingReel = true
        } else {
            showingReelPaywall = true
        }
    }
}
