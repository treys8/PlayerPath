//
//  LoadingOverlay.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Reusable loading overlay component
//

import SwiftUI

/// Full-screen loading overlay with optional message
struct LoadingOverlay: View {
    let message: String?
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(.white)
                
                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .shadow(radius: 10)
        }
        .transition(.opacity)
        .animation(.easeInOut, value: message)
    }
}

/// Inline loading indicator (doesn't cover screen)
struct InlineLoadingView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

/// Small loading button content
struct LoadingButtonContent: View {
    let text: String
    let isLoading: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            }
            Text(text)
        }
        .opacity(isLoading ? 0.6 : 1.0)
        .animation(.easeInOut, value: isLoading)
    }
}

// MARK: - Preview

#Preview("Loading Overlay") {
    ZStack {
        Color.blue.ignoresSafeArea()
        
        LoadingOverlay(message: "Signing out...")
    }
}

#Preview("Loading View") {
    InlineLoadingView(message: "Loading athletes...")
}

#Preview("Loading Button") {
    VStack(spacing: 20) {
        Button {
            // Action
        } label: {
            LoadingButtonContent(text: "Save Changes", isLoading: false)
        }
        .buttonStyle(.borderedProminent)
        
        Button {
            // Action
        } label: {
            LoadingButtonContent(text: "Save Changes", isLoading: true)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true)
    }
    .padding()
}
