//
//  ValidationRequirement.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct ValidationRequirement: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .green : Color(.systemGray3))

            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? .primary : .secondary)
        }
        .animation(.easeInOut(duration: 0.2), value: isMet)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ValidationRequirement(text: "At least 8 characters", isMet: true)
        ValidationRequirement(text: "Contains uppercase letter", isMet: false)
        ValidationRequirement(text: "Contains number", isMet: true)
    }
    .padding()
}
