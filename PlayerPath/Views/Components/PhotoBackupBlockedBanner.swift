//
//  PhotoBackupBlockedBanner.swift
//  PlayerPath
//
//  Shown above the photo grid when the last sync pass skipped photo uploads
//  because cloud storage is full. Photo uploads fail quietly by design (a full
//  quota is not an error to retry), so without this the athlete has no way to
//  know their photos never left the device. Tapping routes to Storage Settings.
//

import SwiftUI

struct PhotoBackupBlockedBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud storage full")
                        .font(.labelLarge)
                        .foregroundColor(.primary)
                    Text("\(count) photo\(count == 1 ? " isn't" : "s aren't") backed up")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
