//
//  TelestrationToolbar.swift
//  PlayerPath
//
//  Drawing tools bar for telestration: color picker, line width,
//  undo, clear, save, and cancel actions.
//

import SwiftUI

struct TelestrationToolbar: View {
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
    let strokeCount: Int
    let onUndo: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var showingClearConfirm = false

    private let colors: [Color] = [.red, .blue, .yellow, .white, .green]
    private let widths: [(label: String, value: CGFloat)] = [
        ("Thin", 2),
        ("Medium", 4),
        ("Thick", 8)
    ]

    private let maxStrokes = 50

    var body: some View {
        VStack(spacing: 8) {
            // Stroke limit warning
            if strokeCount >= maxStrokes - 5 {
                Text("Drawing limit: \(strokeCount)/\(maxStrokes) strokes")
                    .font(.caption2)
                    .foregroundColor(strokeCount >= maxStrokes ? .red : .orange)
            }

            HStack(spacing: 8) {
                // Cancel
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                Divider()
                    .frame(height: 28)
                    .background(Color.white.opacity(0.3))

                // Scrollable tools section (colors, widths, undo, clear)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                Haptics.light()
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                            }
                        }

                        Divider()
                            .frame(height: 28)
                            .background(Color.white.opacity(0.3))

                        ForEach(widths, id: \.value) { item in
                            Button {
                                Haptics.light()
                                lineWidth = item.value
                            } label: {
                                Circle()
                                    .fill(lineWidth == item.value ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: item.value * 2.5 + 6, height: item.value * 2.5 + 6)
                                    .frame(minWidth: 28, minHeight: 28)
                            }
                            .accessibilityLabel("\(item.label) line")
                        }

                        Divider()
                            .frame(height: 28)
                            .background(Color.white.opacity(0.3))

                        Button {
                            onUndo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .disabled(strokeCount == 0)
                        .opacity(strokeCount == 0 ? 0.4 : 1)

                        Button {
                            showingClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .disabled(strokeCount == 0)
                        .opacity(strokeCount == 0 ? 0.4 : 1)
                    }
                }

                // Save — pinned outside ScrollView so it's always visible
                Button {
                    Haptics.success()
                    onSave()
                } label: {
                    Text("Save")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.brandNavy)
                        .clipShape(Capsule())
                }
                .disabled(strokeCount == 0)
                .opacity(strokeCount == 0 ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.black.opacity(0.5))
        .confirmationDialog("Clear Drawing?", isPresented: $showingClearConfirm) {
            Button("Clear All", role: .destructive) { onClear() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
