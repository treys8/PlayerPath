//
//  LiveRangeCard.swift
//  PlayerPath
//
//  Lighter live card for golf range sessions. A range session has no holes
//  and no scoring, so it drops the tournament card's running-score / Score-
//  Hole machinery and offers just Record + End. Live practice rounds and
//  tournaments use the fuller `LiveGameCard` instead. (Named LiveRangeCard to
//  avoid colliding with the coach-side `LiveSessionCard`.)
//

import SwiftUI

struct LiveRangeCard: View {
    let practice: Practice
    var isEnding: Bool = false
    /// Opens the recorder targeting this session, so swings attribute to it.
    var onRecord: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.scenePhase) private var scenePhase

    private var clipCount: Int { practice.videoClips?.count ?? 0 }

    private var subtitle: String? {
        if let course = practice.course, !course.trimmingCharacters(in: .whitespaces).isEmpty {
            return course
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // Pulsing live indicator — same treatment as LiveGameCard for
                // section consistency, but with the range target glyph.
                ZStack {
                    Circle()
                        .fill(ppAccent.opacity(isPulsing ? 0.15 : 0.25))
                        .frame(width: 50, height: 50)
                        .blur(radius: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Circle()
                        .fill(ppAccent.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(ppAccent.opacity(isPulsing ? 0.1 : 0.35))
                        .frame(width: 36, height: 36)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ppAccent)
                        .symbolRenderingMode(.hierarchical)
                }
                .onAppear { if !reduceMotion { isPulsing = true } }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        if !reduceMotion { isPulsing = true }
                    } else {
                        isPulsing = false
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // Shared pill — same live marker as the Games/Practices lists.
                        LiveBadge()
                            .fixedSize()

                        Text("RANGE SESSION")
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(subtitle ?? "Driving Range")
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                        Text(clipCount == 1 ? "1 clip" : "\(clipCount) clips")
                            .font(.bodySmall)
                            .monospacedDigit()
                        if let start = practice.liveStartDate {
                            Text("·")
                                .font(.bodySmall)
                            Text(start, style: .timer)
                                .font(.bodySmall)
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                if let onRecord {
                    Button {
                        Haptics.medium()
                        onRecord()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("Record")
                        }
                        .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(ppAccent))
                    }
                    .buttonStyle(.borderless)
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
                                Text("End Session")
                            }
                        }
                        .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                        .foregroundColor(ppAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        // Secondary to Record: ending is the rarer action.
                        .background(Capsule().fill(ppAccent.opacity(0.12)))
                    }
                    .disabled(isEnding)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        // Same card surface as LiveGameCard; the accent hairline marks it live.
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(ppAccent.opacity(0.45), lineWidth: 1.5)
        )
    }
}
