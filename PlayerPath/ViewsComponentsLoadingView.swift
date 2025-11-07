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
    
    init(title: String = "Setting up your profile...", subtitle: String = "This will only take a moment") {
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    LoadingView()
}