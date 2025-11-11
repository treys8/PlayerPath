//
//  LoadingView.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

struct LoadingView: View {
    let title: String
    let subtitle: String
    let tint: Color
    let systemImage: String?
    
    init(
        title: String = "Setting up your profile...",
        subtitle: String = "This will only take a moment",
        tint: Color = .blue,
        systemImage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.systemImage = systemImage
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 36))
                    .foregroundColor(tint)
            }
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(tint)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    Group {
        LoadingView()
        LoadingView(title: "Syncing data...", subtitle: "Just a moment", tint: .green, systemImage: "arrow.triangle.2.circlepath")
    }
}
