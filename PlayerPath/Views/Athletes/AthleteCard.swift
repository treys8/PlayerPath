//
//  AthleteCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct AthleteCard: View {
    let athlete: Athlete
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // Profile icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }

                VStack(spacing: 6) {
                    Text(athlete.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let created = athlete.createdAt {
                        Text("Created \(created, format: .dateTime.day().month().year())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Created —")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Quick stats if available
                HStack(spacing: 16) {
                    AthleteStatBadge(
                        icon: "video.fill",
                        count: (athlete.videoClips ?? []).count,
                        label: "Videos"
                    )

                    AthleteStatBadge(
                        icon: "sportscourt.fill",
                        count: (athlete.games ?? []).count,
                        label: "Games"
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .appCard(cornerRadius: 16)
            .contextMenu {
                Button {
                    // Open
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                Button {
                    // Toggle live (stub)
                } label: {
                    Label((athlete.games ?? []).first?.isLive == true ? "End Live" : "Mark Live", systemImage: (athlete.games ?? []).first?.isLive == true ? "stop.circle" : "record.circle")
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Select athlete \(athlete.name)")
        .accessibilityHint("Opens this athlete's dashboard")
    }
}
