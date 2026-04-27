//
//  QualityStatItem.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct QualityStatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headingMedium)
                .foregroundStyle(.primary)

            Text(label)
                .font(.labelSmall)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
