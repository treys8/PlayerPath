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
                    Text(timestampList)
                        .font(.footnote)
                        .foregroundColor(.secondary)
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

    private var timestampList: String {
        let stamps = drawings
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.timestamp.formattedTimestamp }
        if stamps.count <= 4 {
            return "Drawings at \(stamps.joined(separator: ", "))"
        }
        let head = stamps.prefix(4).joined(separator: ", ")
        return "Drawings at \(head), +\(stamps.count - 4) more"
    }
}
