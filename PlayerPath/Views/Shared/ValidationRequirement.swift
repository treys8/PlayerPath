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
        HStack {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .foregroundColor(isMet ? .green : .gray)
        }
    }
}
