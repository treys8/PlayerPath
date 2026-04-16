//
//  BulkImportAttach.swift
//  PlayerPath
//
//  ViewModifier that attaches the bulk video-import UI (Photos picker → progress
//  sheet → completion toast) to any view. Owns all presentation state so call
//  sites only need a trigger binding + athlete (and optional game/practice).
//

import SwiftUI
import SwiftData
import PhotosUI

private let maxImportSelection = 20

struct BulkImportAttach: ViewModifier {
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
    var game: Game? = nil
    var practice: Practice? = nil
    @Binding var trigger: Bool

    @State private var showingPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingItems: [PhotosPickerItem] = []
    @State private var showingSheet = false
    @State private var toastMessage: String?
    @State private var toastKind: ToastKind = .success
    @State private var toastTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPicker,
                selection: $pickerItems,
                maxSelectionCount: maxImportSelection,
                matching: .videos,
                preferredItemEncoding: .compatible
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                trigger = false
                guard athlete != nil else { return }
                pickerItems = []
                showingPicker = true
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                pendingItems = newItems
                pickerItems = []
                showingSheet = true
            }
            .sheet(isPresented: $showingSheet) {
                if let athlete = athlete {
                    BulkVideoImportSheet(
                        items: pendingItems,
                        athlete: athlete,
                        game: game,
                        practice: practice
                    ) { succeeded, failed, stoppedForQuota, wasCancelled in
                        let (text, kind) = Self.classify(
                            succeeded: succeeded,
                            failed: failed,
                            stoppedForQuota: stoppedForQuota,
                            wasCancelled: wasCancelled
                        )
                        showToast(text, kind: kind)
                        pendingItems = []
                    }
                    .presentationDetents([.medium])
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

    private func showToast(_ message: String, kind: ToastKind) {
        // Cancel any previous dismissal so a stale timer can't clear this toast.
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4)) {
            toastMessage = message
            toastKind = kind
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) {
                toastMessage = nil
            }
        }
    }

    fileprivate static func classify(succeeded: Int, failed: Int, stoppedForQuota: Bool, wasCancelled: Bool) -> (String, ToastKind) {
        if stoppedForQuota {
            return succeeded > 0
                ? ("\(succeeded) imported — storage full", .warning)
                : ("Storage full — nothing imported", .error)
        }
        if wasCancelled {
            return succeeded > 0
                ? ("Cancelled — \(succeeded) imported", .warning)
                : ("Import cancelled", .warning)
        }
        if failed == 0 && succeeded > 0 {
            return (succeeded == 1 ? "1 video imported" : "\(succeeded) videos imported", .success)
        }
        if succeeded == 0 {
            return ("Import failed", .error)
        }
        return ("\(succeeded) imported, \(failed) failed", .warning)
    }
}

extension View {
    func bulkImportAttach(
        athlete: Athlete?,
        game: Game? = nil,
        practice: Practice? = nil,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(BulkImportAttach(athlete: athlete, game: game, practice: practice, trigger: trigger))
    }
}
