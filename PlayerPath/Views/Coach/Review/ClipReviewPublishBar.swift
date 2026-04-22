//
//  ClipReviewPublishBar.swift
//  PlayerPath
//
//  Pinned bottom action bar for ClipReviewSheet: "Share Now" (publish
//  private→shared), "Save for Later" (keep private, persist note), and
//  an overflow menu for "Discard".
//

import SwiftUI

struct ClipReviewPublishBar: View {
    let isPublishing: Bool
    let isSavingDraft: Bool
    let isDiscarding: Bool
    let onShareNow: () -> Void
    let onSaveForLater: () -> Void
    let onDiscard: () -> Void

    private var isBusy: Bool { isPublishing || isSavingDraft || isDiscarding }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onShareNow) {
                HStack {
                    if isPublishing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Label("Share Now", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.brandNavy)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isBusy)

            HStack(spacing: 10) {
                Button(action: onSaveForLater) {
                    HStack {
                        if isSavingDraft {
                            ProgressView().controlSize(.small)
                        }
                        Text("Save for Later")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundColor(.brandNavy)
                    .cornerRadius(10)
                }
                .disabled(isBusy)

                Menu {
                    Button(role: .destructive, action: onDiscard) {
                        Label("Discard Clip", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .disabled(isBusy)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
