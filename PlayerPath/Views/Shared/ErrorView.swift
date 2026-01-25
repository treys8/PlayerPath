//
//  ErrorView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct ErrorView: View {
    let message: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(.title3).bold()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
