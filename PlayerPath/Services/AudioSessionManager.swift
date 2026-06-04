//
//  AudioSessionManager.swift
//  PlayerPath
//
//  Centralizes the shared AVAudioSession configuration for video playback.
//  Without an explicit `.playback` category the app inherits `.soloAmbient`,
//  which the hardware ring/silent switch SILENCES — so clip / coach / highlight
//  audio (including spoken coaching cues baked into a clip) is inaudible
//  whenever the switch is engaged. Call `configureForPlayback()` when a player
//  appears so review surfaces play through the silent switch (expected
//  behavior, matching Photos / YouTube).
//

import Foundation
import AVFoundation
import os

enum AudioSessionManager {
    private static let log = Logger(subsystem: "com.playerpath.app", category: "AudioSession")

    /// Sets the shared session to `.playback` (movie playback) and activates it
    /// so video audio plays through the silent switch. The category is
    /// process-global and this is idempotent, so it is safe (and intentional) to
    /// call on every player appearance — `AVCaptureSession` temporarily overrides
    /// the category while recording, which is why it is re-asserted per player
    /// rather than only once at launch. Safe to call from any thread.
    static func configureForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            log.error("configureForPlayback failed: \(error.localizedDescription)")
        }
    }
}
