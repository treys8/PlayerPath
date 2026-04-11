//
//  BulkVideoImportSheet.swift
//  PlayerPath
//
//  Modal progress UI for bulk-importing videos from the Photos library.
//  Owns a BulkVideoImportViewModel and dismisses on completion via the
//  onComplete callback so the parent can surface a result toast.
//

import SwiftUI
import SwiftData
import PhotosUI

struct BulkVideoImportSheet: View {
    let items: [PhotosPickerItem]
    let athlete: Athlete
    let onComplete: (_ succeeded: Int, _ failed: Int, _ stoppedForQuota: Bool, _ wasCancelled: Bool) -> Void

    @State private var viewModel = BulkVideoImportViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandNavy)

                Text("Importing Videos")
                    .font(.title2)
                    .fontWeight(.bold)

                if case .importing(let current, let total) = viewModel.status {
                    VStack(spacing: 12) {
                        ProgressView(value: Double(current), total: Double(total))
                            .tint(.brandNavy)
                            .padding(.horizontal, 40)
                        Text("\(current) of \(total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                if case .importing = viewModel.status {
                    Button(role: .destructive) {
                        viewModel.cancel()
                    } label: {
                        Text("Cancel")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                }
            }
            .interactiveDismissDisabled()
            .task {
                await viewModel.runImport(items: items, athlete: athlete, modelContext: modelContext)
                if case .completed(let succeeded, let failed, let quota, let cancelled) = viewModel.status {
                    onComplete(succeeded, failed, quota, cancelled)
                    dismiss()
                }
            }
        }
    }
}
