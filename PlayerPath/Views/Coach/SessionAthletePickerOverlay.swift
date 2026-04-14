//
//  SessionAthletePickerOverlay.swift
//  PlayerPath
//
//  Quick athlete picker shown after recording a clip during a live session.
//  Appears as a translucent overlay on the camera so the coach can
//  tag which athlete the clip belongs to with minimal friction.
//

import SwiftUI

struct SessionAthletePickerOverlay: View {
    let athletes: [(id: String, name: String)]
    let lastSelectedID: String?
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var selectedID: String?
    /// Prevents double-tap from firing onSelect twice — which would enqueue the same
    /// clip to two athlete folders.
    @State private var hasSelected = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Text("Who is this clip for?")
                    .font(.headline)
                    .foregroundColor(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(athletes, id: \.id) { athlete in
                            Button {
                                guard !hasSelected else { return }
                                hasSelected = true
                                selectedID = athlete.id
                                Haptics.light()
                                onSelect(athlete.id)
                            } label: {
                                HStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected(athlete.id) ? Color.brandNavy : Color.white.opacity(0.2))
                                            .frame(width: 32, height: 32)
                                        Text(String(athlete.name.prefix(1)).uppercased())
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(isSelected(athlete.id) ? .white : .white.opacity(0.9))
                                    }
                                    Text(firstName(athlete.name))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(isSelected(athlete.id) ? Color.brandNavy.opacity(0.3) : Color.white.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected(athlete.id) ? Color.brandNavy : Color.clear, lineWidth: 2)
                                )
                            }
                            .disabled(hasSelected)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    guard !hasSelected else { return }
                    onCancel()
                } label: {
                    Text("Discard Clip")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 4)
                .disabled(hasSelected)
            }
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .onAppear {
            selectedID = lastSelectedID
        }
    }

    private func isSelected(_ id: String) -> Bool {
        if let selectedID { return selectedID == id }
        return lastSelectedID == id
    }

    private func firstName(_ name: String) -> String {
        name.components(separatedBy: " ").first ?? name
    }
}
