//
//  StatusChip.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}
