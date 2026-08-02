//
//  LiveBadge.swift
//  PlayerPath
//
//  Pulsing "LIVE" capsule shared by the games and practices lists. Lives here
//  rather than beside either row so both stay in step — a live round and a live
//  practice should read identically at a glance.
//

import SwiftUI

// Pulsing live badge — terracotta accent (live = significance, the one accent).
struct LiveBadge: View {
    @Environment(\.ppAccent) private var ppAccent
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.ppCaptionBold)
        }
        .foregroundStyle(.white)
        .badgeMedium()
        .background(Capsule().fill(ppAccent))
        .opacity(isPulsing ? 0.7 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
