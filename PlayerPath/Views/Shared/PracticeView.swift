//
//  PracticeView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct PracticeView: View {
    let athlete: Athlete
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Practice")
                .font(.title)
                .fontWeight(.bold)
            Text("Practice tracking coming soon for \(athlete.name)")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }
}
