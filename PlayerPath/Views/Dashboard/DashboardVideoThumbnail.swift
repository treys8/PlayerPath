//
//  DashboardVideoThumbnail.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct DashboardVideoThumbnail: View {
    let video: VideoClip
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .transition(.opacity.combined(with: .scale))
            } else {
                LinearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .transition(.opacity)
            }

            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.white)
                .shadow(radius: 2)
                .symbolEffect(.bounce, options: .speed(0.5))
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await load() }
    }

    private func load() async {
        guard !isLoading, image == nil else { return }
        isLoading = true
        defer { isLoading = false }

        guard let path = video.thumbnailPath else { return }

        do {
            let img = try await ThumbnailCache.shared.loadThumbnail(at: path)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    image = img
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to load thumbnail: \(error.localizedDescription)")
            #endif
        }
    }
}
