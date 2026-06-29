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
            case .warning: return Theme.warning
            case .error:   return .red
            }
        }
    }

    let athlete: Athlete?
    var game: Game? = nil
    var practice: Practice? = nil
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

    // Post-import backfill prompt: photos whose EXIF capture date matched no
    // season (and fell back to the active season) on a non-pre-pinned import.
    @State private var unmatchedPhotos: [Photo] = []
    @State private var unmatchedEarliest: Date?
    @State private var unmatchedLatest: Date?
    @State private var showingBackfill = false

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
                                .font(.bodyMedium)
                                .foregroundColor(.white)
                                .monospacedDigit()

                            Button(role: .destructive) {
                                importTask?.cancel()
                            } label: {
                                Text("Cancel")
                                    .font(.headingSmall)
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
                        .font(.labelLarge)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(toastKind.color, in: Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingBackfill) {
                if let athlete {
                    BackfillSeasonPromptView(
                        athlete: athlete,
                        unmatchedCount: unmatchedPhotos.count,
                        dateRange: (unmatchedEarliest ?? Date())...(unmatchedLatest ?? Date()),
                        currentSeasonName: athlete.activeSeason?.displayName ?? "your current season",
                        onResolve: reroute
                    )
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
        // Pre-pinned imports (a specific game/practice/season was supplied) never
        // prompt — the caller already chose the target.
        let prePinned = game != nil || practice != nil || season != nil
        var saved = 0
        var failed = 0
        unmatchedPhotos = []
        unmatchedEarliest = nil
        unmatchedLatest = nil

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            importProgress = (index + 1, items.count)

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }

                // Pull EXIF capture date first so we can route the photo to the
                // right season. A preset game/practice wins (the photo inherits
                // that event's season — mirrors BulkVideoImportViewModel); then
                // an explicit `season` prop; then match by capture date; then
                // activeSeason.
                let exifDate = service.extractCaptureDate(from: data)
                let resolvedSeason: Season?
                // Tracks the silent-misfile case: a non-pre-pinned photo whose
                // EXIF date matched no season and fell back to the active one.
                var dateUnmatched = false
                if let game {
                    resolvedSeason = game.season ?? athlete.activeSeason
                } else if let practice {
                    resolvedSeason = practice.season ?? athlete.activeSeason
                } else if let season {
                    resolvedSeason = season
                } else if let exifDate {
                    let dateMatch = Season.season(containing: exifDate, in: allSeasons)
                    resolvedSeason = dateMatch ?? athlete.activeSeason
                    // Only flag when genuinely OLDER than the current season (see
                    // BulkVideoImportViewModel): newer-than-any/future-dated photos
                    // stay on the active season.
                    if let start = athlete.activeSeason?.startDate {
                        dateUnmatched = (dateMatch == nil && exifDate < start)
                    }
                } else {
                    resolvedSeason = athlete.activeSeason
                }

                // Second-precision EXIF dates tie on sort for burst imports;
                // nudge by a microsecond per index so the list remains stable.
                let nudgedDate = exifDate?.addingTimeInterval(Double(index) / 1_000_000.0)

                let photo = try await service.savePhotoFromData(
                    data,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    practice: practice,
                    season: resolvedSeason,
                    captureDate: nudgedDate
                )
                saved += 1

                if !prePinned, dateUnmatched, let exifDate {
                    unmatchedPhotos.append(photo)
                    unmatchedEarliest = min(unmatchedEarliest ?? exifDate, exifDate)
                    unmatchedLatest = max(unmatchedLatest ?? exifDate, exifDate)
                }
            } catch {
                ErrorHandlerService.shared.handle(error, context: "BulkPhotoImportAttach.import", showAlert: false)
                failed += 1
            }
        }

        isImporting = false
        importTask = nil
        showResult(saved: saved, failed: failed)

        // Offer to re-home photos that were filed on the current season only
        // because their capture dates matched no season.
        if !unmatchedPhotos.isEmpty, athlete.activeSeason != nil {
            showingBackfill = true
        }
    }

    /// Re-homes the date-unmatched photos to the chosen season (nil = keep on
    /// current). Marks them dirty and kicks off a background metadata sync.
    private func reroute(to season: Season?) {
        defer { unmatchedPhotos = [] }
        guard let season else { return }
        for photo in unmatchedPhotos {
            photo.season = season
            photo.needsSync = true
            photo.version += 1
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "BulkPhotoImport.reroute")
        if let user = athlete?.user {
            Task {
                do {
                    try await SyncCoordinator.shared.syncPhotos(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "BulkPhotoImport.syncPhotos", showAlert: false)
                }
            }
        }
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
        game: Game? = nil,
        practice: Practice? = nil,
        season: Season? = nil,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(BulkPhotoImportAttach(athlete: athlete, game: game, practice: practice, season: season, trigger: trigger))
    }
}
