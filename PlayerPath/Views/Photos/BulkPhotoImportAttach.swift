//
//  BulkPhotoImportAttach.swift
//  PlayerPath
//
//  ViewModifier mirror of BulkImportAttach for photos. Attaches a PhotosPicker
//  → progress overlay → completion toast pipeline and routes every imported
//  photo to the caller-supplied season (falling back to the athlete's active
//  season). Call sites supply a trigger binding — flipping it to true opens
//  the library picker.
//

import SwiftUI
import SwiftData
import PhotosUI

private let maxPhotoImportSelection = 20

struct BulkPhotoImportAttach: ViewModifier {
    fileprivate enum ToastKind {
        case success, warning, error

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error:   return .red
            }
        }
    }

    let athlete: Athlete?
    var season: Season? = nil
    @Binding var trigger: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var showingPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var importTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @State private var toastKind: ToastKind = .success
    @State private var toastTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPicker,
                selection: $pickerItems,
                maxSelectionCount: maxPhotoImportSelection,
                matching: .images
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                trigger = false
                guard athlete != nil else { return }
                pickerItems = []
                showingPicker = true
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty, let athlete else { return }
                let items = newItems
                pickerItems = []
                startImport(items, athlete: athlete)
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView(
                                value: Double(importProgress.current),
                                total: Double(max(importProgress.total, 1))
                            )
                            .tint(.white)
                            .frame(width: 160)

                            Text("Importing \(importProgress.current) of \(importProgress.total)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .monospacedDigit()

                            Button(role: .destructive) {
                                importTask?.cancel()
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = toastMessage {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(toastKind.color, in: Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private func startImport(_ items: [PhotosPickerItem], athlete: Athlete) {
        importProgress = (0, items.count)
        isImporting = true
        importTask = Task { @MainActor in
            await importPhotos(items, athlete: athlete)
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem], athlete: Athlete) async {
        let service = PhotoPersistenceService()
        let allSeasons = athlete.seasons ?? []
        var saved = 0
        var failed = 0

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            importProgress = (index + 1, items.count)

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }

                // Pull EXIF capture date first so we can route the photo to the
                // right season. An explicit `season` prop from the call site
                // wins; otherwise match by capture date; otherwise activeSeason.
                let exifDate = service.extractCaptureDate(from: data)
                let resolvedSeason: Season?
                if let season {
                    resolvedSeason = season
                } else if let exifDate {
                    resolvedSeason = Season.season(containing: exifDate, in: allSeasons) ?? athlete.activeSeason
                } else {
                    resolvedSeason = athlete.activeSeason
                }

                // Second-precision EXIF dates tie on sort for burst imports;
                // nudge by a microsecond per index so the list remains stable.
                let nudgedDate = exifDate?.addingTimeInterval(Double(index) / 1_000_000.0)

                _ = try await service.savePhotoFromData(
                    data,
                    context: modelContext,
                    athlete: athlete,
                    season: resolvedSeason,
                    captureDate: nudgedDate
                )
                saved += 1
            } catch {
                ErrorHandlerService.shared.handle(error, context: "BulkPhotoImportAttach.import", showAlert: false)
                failed += 1
            }
        }

        isImporting = false
        importTask = nil
        showResult(saved: saved, failed: failed)
    }

    private func showResult(saved: Int, failed: Int) {
        if saved == 0 && failed == 0 { return }
        let text: String
        let kind: ToastKind
        if saved > 0 && failed == 0 {
            text = saved == 1 ? "Photo imported" : "\(saved) photos imported"
            kind = .success
        } else if saved > 0 && failed > 0 {
            text = "Imported \(saved). \(failed) failed."
            kind = .warning
        } else {
            text = "Could not import photos"
            kind = .error
        }
        showToast(text, kind: kind)
    }

    private func showToast(_ message: String, kind: ToastKind) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4)) {
            toastMessage = message
            toastKind = kind
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { toastMessage = nil }
        }
    }
}

extension View {
    func bulkPhotoImportAttach(
        athlete: Athlete?,
        season: Season? = nil,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(BulkPhotoImportAttach(athlete: athlete, season: season, trigger: trigger))
    }
}
