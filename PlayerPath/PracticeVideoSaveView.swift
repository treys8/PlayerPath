//
//  PracticeVideoSaveView.swift
//  PlayerPath
//
//  Glass overlay shown after trimming a practice recording.
//  Replaces PlayResultOverlayView for practice context — no play result needed,
//  just an optional note the athlete can add before saving or discarding.
//

import SwiftUI
import AVFoundation
import UIKit

struct PracticeVideoSaveView: View {
    let videoURL: URL
    let athlete: Athlete?
    let practice: Practice?
    let onSave: (String?) -> Void
    let onDiscard: () -> Void

    @State private var noteText: String = ""
    @State private var showContent = false
    @State private var isSaving = false
    @State private var thumbnail: UIImage?
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        ZStack {
            // Thumbnail background
            Group {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.3))
            .onAppear { loadThumbnail() }

            // Info header
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.baseball")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Text("Practice Session")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        if let date = practice?.date {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                                Text(date, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        if let name = athlete?.name {
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.black.opacity(0.5), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                }
                Spacer()
            }

            // Bottom glass panel
            VStack {
                Spacer()
                glassPanel
                    .padding(.horizontal, 16)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showContent = true
                        }
                    }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 16) }

            // Back / Discard button — top-leading
            VStack {
                HStack {
                    Button {
                        Haptics.warning()
                        onDiscard()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Discard")
                                .font(.body)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .disabled(isSaving)
                    Spacer()
                }
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 16)

            // Saving overlay
            if isSaving {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Saving...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSaving)
        .onAppear {
            PlayerPathAppDelegate.orientationLock = .portrait
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        .onDisappear {
            PlayerPathAppDelegate.orientationLock = .allButUpsideDown
        }
        .onTapGesture {
            noteIsFocused = false
        }
    }

    // MARK: - Glass panel

    private var glassPanel: some View {
        VStack(spacing: 18) {
            // Header
            VStack(spacing: 6) {
                Text("Practice Recording")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Add an optional note before saving")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Note input
            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("What were you working on? (optional)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteText)
                    .focused($noteIsFocused)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(minHeight: 60, maxHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 4)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { noteIsFocused = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Action buttons
            HStack(spacing: 12) {
                PlayResultActionButton(title: "Skip", icon: "forward", style: .secondary) {
                    save(note: nil)
                }
                .disabled(isSaving)

                PlayResultActionButton(title: noteText.isEmpty ? "Save" : "Save with Note", icon: "checkmark.circle.fill", style: .primary) {
                    save(note: noteText.isEmpty ? nil : noteText)
                }
                .disabled(isSaving)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    ))
                VStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .top, endPoint: .center))
                        .frame(height: 100)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
    }

    // MARK: - Helpers

    private func save(note: String?) {
        noteIsFocused = false
        isSaving = true
        onSave(note)
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1080, height: 1920)
            if let cgImage = try? await generator.image(at: .zero).image {
                await MainActor.run {
                    thumbnail = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
