//
//  LiveSessionCard.swift
//  PlayerPath
//
//  Dashboard card for active coach sessions. Mirrors LiveGameCard
//  for athletes with pulsing indicator, session info, and actions.
//

import SwiftUI

struct LiveSessionCard: View {
    let session: CoachSession
    var isEnding: Bool = false
    var onEnd: (() -> Void)?
    var onEditNotes: (() -> Void)?
    var onRecord: (() -> Void)?

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ppAccent) private var ppAccent

    private var isLive: Bool { session.status == .live }
    private var accentColor: Color { isLive ? ppAccent : Theme.textSecondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: live indicator, session info, and (when ended) a
            // chevron. The info column gets the full card width here so the
            // LIVE badge, name, and metadata never compete with the action
            // buttons for space — actions live on their own row below.
            HStack(spacing: 14) {
                // Pulsing indicator
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isPulsing ? 0.15 : 0.25))
                        .frame(width: 50, height: 50)
                        .blur(radius: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(accentColor.opacity(isPulsing ? 0.1 : 0.35))
                        .frame(width: 36, height: 36)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Image(systemName: isLive ? "record.circle" : "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .onAppear { if isLive && !reduceMotion { isPulsing = true } }
                .onChange(of: scenePhase) { _, newPhase in
                    isPulsing = isLive && newPhase == .active && !reduceMotion
                }

                // Session info
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if isLive {
                            // Shared pill — same live marker as the athlete live cards.
                            LiveBadge()
                                .fixedSize()
                        } else {
                            Text("SESSION ENDED")
                                .font(.caption2)
                                .fontWeight(.black)
                                .foregroundColor(accentColor)
                                .fixedSize()
                                .badgeSmall()
                                .background(Capsule().fill(accentColor.opacity(0.12)))
                                // Intrinsic width so the label can never wrap.
                                .fixedSize()
                        }

                        if isLive {
                            Text("SESSION")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(session.athleteNamesSummary)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.caption2)
                            Text("\(session.clipCount) clip\(session.clipCount == 1 ? "" : "s")")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .fixedSize()

                        if isLive, let startedAt = session.startedAt {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                Text(startedAt, style: .timer)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        }

                        if let onEditNotes {
                            Button {
                                onEditNotes()
                            } label: {
                                Image(systemName: "note.text")
                                    .font(.caption2)
                                    .foregroundColor(ppAccent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit session notes")
                        }
                    }
                    .foregroundColor(.secondary)

                    if let notes = session.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .italic()
                    }
                }

                Spacer()

                if !isLive {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action row — full-width CTAs on their own line so they never
            // crowd the name or metadata. Side-by-side when both present.
            if isLive, onRecord != nil || onEnd != nil {
                HStack(spacing: 10) {
                    if let onRecord {
                        Button {
                            Haptics.medium()
                            onRecord()
                        } label: {
                            Label("Record", systemImage: "video.fill")
                                .font(.caption)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(ppAccent))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Record clip")
                    }

                    if let onEnd {
                        Button {
                            Haptics.medium()
                            onEnd()
                        } label: {
                            Group {
                                if isEnding {
                                    ProgressView().tint(ppAccent)
                                } else {
                                    Text("End")
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ppAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(ppAccent.opacity(0.12)))
                        }
                        .disabled(isEnding)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        // Same card surface as the athlete live cards; the accent hairline marks it live.
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(accentColor.opacity(0.45), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isLive ? "Live" : "Ended") session with \(session.athleteNamesSummary). \(session.clipCount) clip\(session.clipCount == 1 ? "" : "s").")
    }
}
