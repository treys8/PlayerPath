//
//  ClipReviewTelestrationSection.swift
//  PlayerPath
//
//  Collapsible telestration section for ClipReviewSheet. Shows the
//  drawings the coach has already attached to the private clip and a
//  button to capture the current frame and launch the drawing overlay.
//

import SwiftUI

struct ClipReviewTelestrationSection: View {
    let drawings: [VideoAnnotation]
    let isLoading: Bool
    let isStartingTelestration: Bool
    let canStart: Bool
    @Binding var isExpanded: Bool
    let onStartDrawing: () -> Void
    /// Tap on a saved drawing row → seek the player + overlay it on the video.
    /// Wired from `ClipReviewSheet.showDrawing(for:)`.
    let onTapDrawing: (VideoAnnotation) -> Void

    private var sortedDrawings: [VideoAnnotation] {
        drawings.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading drawings…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                } else if drawings.isEmpty {
                    Text("Draw on a frame to highlight mechanics or positioning.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(sortedDrawings) { drawing in
                            Button {
                                onTapDrawing(drawing)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "pencil.tip")
                                        .font(.subheadline)
                                        .foregroundColor(.brandNavy)
                                    Text(drawing.timestamp.formattedTimestamp)
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View drawing at \(drawing.timestamp.formattedTimestamp)")
                        }
                    }
                    .padding(.top, 6)
                }

                Button(action: onStartDrawing) {
                    HStack {
                        if isStartingTelestration {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "pencil.tip")
                        }
                        Text(drawings.isEmpty ? "Draw on Current Frame" : "Draw on Another Frame")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.brandNavy.opacity(0.1))
                    .foregroundColor(.brandNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canStart || isStartingTelestration)
                .padding(.top, 4)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label(headerTitle, systemImage: "pencil.tip.crop.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var headerTitle: String {
        drawings.isEmpty ? "Telestration" : "Telestration • \(drawings.count)"
    }
}
