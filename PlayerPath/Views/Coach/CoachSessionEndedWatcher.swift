//
//  CoachSessionEndedWatcher.swift
//  PlayerPath
//
//  Watches the session a coach recorder is recording into. When it stops being
//  live (ended or completed on another device, an athlete revoked access, the
//  abandoned-session cleanup), it warns, then closes the recorder. A clip
//  already recorded can still be saved; uploadClip parks a revoked one in
//  coach_failed_uploads.
//
//  Confirms with a server read before warning: `activeSession` also goes nil
//  for listener teardown on backgrounding and while the listener restarts, and
//  neither of those means the session ended.
//

import SwiftUI

struct CoachSessionEndedWatcher: ViewModifier {
    /// The session being recorded into. Nil (athlete recording) = inert.
    let sessionID: String?
    /// A recorded clip is in hand (trimming / picking an athlete).
    let hasUnsavedClip: Bool
    /// A clip is already uploading; it dismisses on its own when done.
    let isSaving: Bool
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showingEnded = false
    @State private var didWarn = false
    @State private var isVerifying = false

    func body(content: Content) -> some View {
        content
            .onChange(of: CoachSessionManager.shared.activeSession) { _, newValue in
                guard scenePhase == .active else { return }
                if let newValue, newValue.id == sessionID, newValue.status == .live { return }
                verifySessionEnded()
            }
            .onChange(of: scenePhase) { _, phase in
                // Ended while backgrounded: the restarted listener may never
                // report a change for it, so check on return.
                if phase == .active { verifySessionEnded() }
            }
            .alert("Session Ended", isPresented: $showingEnded) {
                if hasUnsavedClip {
                    // Stay: finishing the clip saves it and closes the recorder.
                    Button("Save Clip", role: .cancel) {}
                    Button("Discard Clip", role: .destructive) { onClose() }
                } else {
                    Button("OK", role: .cancel) { onClose() }
                }
            } message: {
                Text(hasUnsavedClip
                     ? "This session was ended on another device or by an athlete. You can still save the clip you just recorded."
                     : "This session was ended on another device or by an athlete, so the camera will close.")
            }
    }

    private func verifySessionEnded() {
        guard let sessionID, !didWarn, !isSaving, !isVerifying else { return }
        isVerifying = true
        Task {
            defer { isVerifying = false }
            let session: CoachSession?
            do {
                session = try await CoachSessionManager.shared.refreshSession(id: sessionID)
            } catch {
                // Offline or a read error: no evidence it ended, so say nothing.
                return
            }
            if let session, session.status == .live { return }
            guard !didWarn, !isSaving else { return }
            didWarn = true
            Haptics.warning()
            showingEnded = true
        }
    }
}

extension View {
    /// Warn-then-close when a coach recorder's session ends elsewhere.
    func coachSessionEndedWatcher(
        sessionID: String?,
        hasUnsavedClip: Bool,
        isSaving: Bool,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(CoachSessionEndedWatcher(
            sessionID: sessionID,
            hasUnsavedClip: hasUnsavedClip,
            isSaving: isSaving,
            onClose: onClose
        ))
    }
}
