//
//  ClipReviewPublishBar.swift
//  PlayerPath
//
//  Pinned bottom action bar for a coach's own unpublished draft in
//  CoachVideoPlayerView: "Share Now" (publish private→shared), "Save for Later"
//  (keep private), and an overflow menu for "Discard". iOS 26 draws the three
//  as Liquid Glass buttons; earlier OSes keep the filled buttons.
//

import SwiftUI

struct ClipReviewPublishBar: View {
    let isPublishing: Bool
    let isSavingDraft: Bool
    let isDiscarding: Bool
    let onShareNow: () -> Void
    let onSaveForLater: () -> Void
    let onDiscard: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    private var isBusy: Bool { isPublishing || isSavingDraft || isDiscarding }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                glassBody
            } else {
                legacyBody
            }
        }
        .disabled(isBusy)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - iOS 26

    @available(iOS 26, *)
    private var glassBody: some View {
        VStack(spacing: 10) {
            Button(action: onShareNow) {
                shareLabel.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(ppAccent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button(action: onSaveForLater) {
                    saveLabel.frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(ppAccent)
                .controlSize(.large)

                Menu {
                    discardMenuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.primary)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityLabel("More actions")
            }
        }
    }

    // MARK: - Before iOS 26

    private var legacyBody: some View {
        VStack(spacing: 10) {
            Button(action: onShareNow) {
                shareLabel
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(ppAccent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            HStack(spacing: 10) {
                Button(action: onSaveForLater) {
                    saveLabel
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(ppAccent)
                        .cornerRadius(10)
                }

                Menu {
                    discardMenuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Shared labels

    private var shareLabel: some View {
        HStack {
            if isPublishing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            Label("Share Now", systemImage: "paperplane.fill")
                .fontWeight(.semibold)
        }
    }

    private var saveLabel: some View {
        HStack {
            if isSavingDraft {
                ProgressView().controlSize(.small)
            }
            Text("Save for Later")
                .fontWeight(.medium)
        }
    }

    private var discardMenuContent: some View {
        Button(role: .destructive, action: onDiscard) {
            Label("Discard Clip", systemImage: "trash")
        }
    }
}
