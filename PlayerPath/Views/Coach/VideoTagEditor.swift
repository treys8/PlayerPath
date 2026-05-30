//
//  VideoTagEditor.swift
//  PlayerPath
//
//  Reusable tag picker sheet for adding/removing tags on videos.
//  Sport-aware: shows golf drill types / tag suggestions when `isGolf` is set,
//  baseball ones otherwise (see VideoTagEditor+Golf.swift).
//

import SwiftUI

struct VideoTagEditor: View {
    @Binding var selectedTags: [String]
    @Binding var drillType: String?
    var isGolf: Bool = false
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var customTag = ""

    /// Drill options for the current sport, as (rawValue, displayName) pairs so
    /// the row/selection logic stays sport-agnostic.
    private var drillOptions: [(raw: String, name: String)] {
        isGolf
            ? GolfDrillType.allCases.map { ($0.rawValue, $0.displayName) }
            : DrillType.allCases.map { ($0.rawValue, $0.displayName) }
    }

    private var tagSuggestions: [String] {
        isGolf ? VideoTag.golfSuggestions : VideoTag.suggestions
    }

    var body: some View {
        NavigationStack {
            List {
                // Drill Type
                Section("Drill Type") {
                    ForEach(drillOptions, id: \.raw) { drill in
                        Button {
                            drillType = drillType == drill.raw ? nil : drill.raw
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(drill.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if drillType == drill.raw {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.brandNavy)
                                }
                            }
                        }
                    }
                }

                // Quick Tags
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tagSuggestions, id: \.self) { tag in
                            TagChip(
                                text: tag,
                                isSelected: selectedTags.contains(tag),
                                onTap: { toggleTag(tag) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Custom Tag
                Section("Custom Tag") {
                    HStack {
                        TextField("Add custom tag", text: $customTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { addCustomTag() }

                        if !customTag.isEmpty {
                            Button {
                                addCustomTag()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }
                }

                // Active Tags
                if !selectedTags.isEmpty {
                    Section("Active Tags") {
                        ForEach(selectedTags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button {
                                    toggleTag(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave?()
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
        Haptics.selection()
    }

    private func addCustomTag() {
        let trimmed = customTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !selectedTags.contains(trimmed) else { return }
        selectedTags.append(trimmed)
        customTag = ""
        Haptics.selection()
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.brandNavy.opacity(0.2) : Color(.systemGray5))
                .foregroundColor(isSelected ? .brandNavy : .primary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.brandNavy : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Constants

enum DrillType: String, CaseIterable {
    case battingPractice = "batting_practice"
    case teeWork = "tee_work"
    case softToss = "soft_toss"
    case liveBP = "live_bp"
    case bullpen = "bullpen"
    case fieldingDrill = "fielding_drill"
    case catchPlay = "catch_play"
    case baseRunning = "base_running"
    case situational = "situational"

    var displayName: String {
        switch self {
        case .battingPractice: return "Batting Practice"
        case .teeWork: return "Tee Work"
        case .softToss: return "Soft Toss"
        case .liveBP: return "Live BP"
        case .bullpen: return "Bullpen"
        case .fieldingDrill: return "Fielding Drill"
        case .catchPlay: return "Catch & Play"
        case .baseRunning: return "Base Running"
        case .situational: return "Situational"
        }
    }
}

enum VideoTag {
    static let suggestions: [String] = [
        "mechanics", "swing", "approach", "timing",
        "pitching", "fielding", "throwing", "footwork",
        "good rep", "needs work", "highlight", "slow-mo"
    ]
}
