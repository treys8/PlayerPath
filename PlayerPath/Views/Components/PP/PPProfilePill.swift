//
//  PPProfilePill.swift
//  PlayerPath
//
//  Visual overhaul — the profile pill.
//  Top-left header element: a small initial avatar + name + chevron. Tapping it
//  is the athlete switcher affordance. Self-contained (initials avatar); the
//  caller wires the tap action.
//

import SwiftUI

struct PPProfilePill: View {
    let name: String
    var subtitle: String?
    var action: (() -> Void)?

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: .spacingSmall) {
                avatar
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).smallCapsLabel()
                    }
                }
                if action != nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private var avatar: some View {
        Circle()
            .fill(ppAccent.opacity(0.15))
            .frame(width: .profileSmall, height: .profileSmall)
            .overlay(
                Text(initials)
                    .font(.ppSubheadline)
                    .foregroundStyle(ppAccent)
            )
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
