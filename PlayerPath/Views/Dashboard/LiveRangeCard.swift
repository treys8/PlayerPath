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
                        .fill(Color.red.opacity(isPulsing ? 0.15 : 0.25))
                        .frame(width: 50, height: 50)
                        .blur(radius: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(Color.red.opacity(isPulsing ? 0.1 : 0.35))
                        .frame(width: 36, height: 36)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.green)
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
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .opacity(isPulsing ? 0.5 : 1.0)

                            Text("LIVE")
                                .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                                .foregroundColor(.red)
                                .fixedSize()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
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
                        .background(
                            LinearGradient(
                                colors: [.brandNavy, .brandNavy.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .brandNavy.opacity(0.3), radius: 4, x: 0, y: 2)
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
                                ProgressView().tint(.white)
                            } else {
                                Text("End Session")
                            }
                        }
                        .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [.red, .red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isEnding)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.1), Color.green.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(Color.green.opacity(0.4), lineWidth: 2)
        )
        .shadow(color: .green.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}
