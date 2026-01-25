//
//  AthleteRow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct AthleteRow: View {
    let athlete: Athlete
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(athlete.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let created = athlete.createdAt {
                        Text("Created \(created.formatted(.dateTime.day().month().year()))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
