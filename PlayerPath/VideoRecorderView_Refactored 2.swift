import SwiftUI

struct VideoRecorderViewSimple: View {
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "video.badge.plus")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 64, weight: .regular))
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Video Recorder")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)

                        if athlete == nil && game == nil && practice == nil {
                            Text("No context selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if athlete != nil || game != nil || practice != nil {
                        HStack(spacing: 8) {
                            if let athlete {
                                Label(athlete.name, systemImage: "person.fill")
                            }
                            if game != nil {
                                Label("Game", systemImage: "sportscourt")
                            }
                            if practice != nil {
                                Label("Practice", systemImage: "figure.run")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityElement(children: .combine)
                    }

                    VStack(spacing: 12) {
                        Button {
                            // startRecording()
                        } label: {
                            Label("Start Recording", systemImage: "record.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(true)
                        .opacity(0.6)

                        Button {
                            // importFromLibrary()
                        } label: {
                            Label("Import from Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Text("Video recording feature is coming soon.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Record Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // showHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .background(Color(.systemBackground))
        }
    }
}

#Preview {
    VideoRecorderViewSimple(athlete: nil, game: nil, practice: nil)
}
