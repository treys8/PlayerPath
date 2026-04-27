//
//  RetrimSavedClipFlow.swift
//  PlayerPath
//
//  Presents the re-trim UX for an already-saved clip: confirmation →
//  PreUploadTrimmerView → progress overlay → done. Calls ClipTrimService
//  for the persistence pipeline.
//

import SwiftUI
import SwiftData

@MainActor
struct RetrimSavedClipFlow: View {
    let clip: VideoClip
    let athlete: Athlete

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // ObservedObject subscription so .onChange(of:) fires when
    // VideoCloudManager publishes upload progress during the .uploadingVideo stage.
    @ObservedObject private var cloudManager = VideoCloudManager.shared

    @State private var phase: Phase = .confirming
    @State private var currentStage: ClipTrimService.Progress.Stage = .replacingFile
    @State private var errorMessage: String?
    @State private var uploadPercent: Double = 0

    private enum Phase {
        case confirming
        case trimming
        case saving
        case failed
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .confirming:
                confirmationCard
            case .trimming:
                PreUploadTrimmerView(
                    videoURL: clip.resolvedFileURL,
                    onSave: { trimmedURL in
                        phase = .saving
                        Task { await runPersistence(trimmedURL: trimmedURL) }
                    },
                    onSkip: {
                        // Should never be reached — hideSkipButton is true.
                        dismiss()
                    },
                    onCancel: {
                        dismiss()
                    },
                    hideSkipButton: true
                )
            case .saving:
                savingOverlay
            case .failed:
                failureCard
            }
        }
        .onChange(of: cloudManager.uploadProgress[clip.id]) { _, newValue in
            if phase == .saving, currentStage == .uploadingVideo, let newValue {
                uploadPercent = newValue
            }
        }
    }

    // MARK: - Confirmation

    private var confirmationCard: some View {
        VStack(spacing: 24) {
            Image(systemName: "scissors")
                .font(.system(size: 48))
                .foregroundStyle(.white)

            Text("Trim this clip?")
                .font(.displayMedium)
                .foregroundStyle(.white)

            Text("This will update the video for you and anyone you've shared it with. Notes and comments will be kept.")
                .font(.bodyLarge)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    Haptics.medium()
                    phase = .trimming
                } label: {
                    Text("Continue")
                        .font(.headingMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient.primaryButton)
                        )
                }

                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Saving overlay

    private var savingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("Saving changes…")
                .font(.headingLarge)
                .foregroundStyle(.white)

            Text(currentStage.rawValue)
                .font(.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))

            if currentStage == .uploadingVideo {
                ProgressView(value: uploadPercent)
                    .tint(.white)
                    .frame(maxWidth: 220)
                Text("\(Int(uploadPercent * 100))%")
                    .font(.bodySmall)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(40)
    }

    // MARK: - Failure

    private var failureCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text("Couldn't save the trim")
                .font(.headingLarge)
                .foregroundStyle(.white)
            if let errorMessage {
                Text(errorMessage)
                    .font(.bodyMedium)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Close") { dismiss() }
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 30)
                .background(Capsule().fill(.white.opacity(0.15)))
        }
    }

    // MARK: - Persistence

    private func runPersistence(trimmedURL: URL) async {
        do {
            try await ClipTrimService.applyTrim(
                to: clip,
                trimmedSourceURL: trimmedURL,
                athlete: athlete,
                context: modelContext
            ) { progress in
                currentStage = progress.stage
            }
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }
}
