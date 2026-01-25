//
//  VideoQualityPickerView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct VideoQualityPickerView: View {
    @Binding var selectedQuality: UIImagePickerController.QualityType
    @Environment(\.dismiss) private var dismiss
    
    // Quality mapping
    private let qualities: [UIImagePickerController.QualityType] = [
        .typeHigh, .typeMedium, .typeLow, .type640x480
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker section
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Quality")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text("Choose the video quality for your recordings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(qualities, id: \.self) { quality in
                            Text(qualityShortName(for: quality)).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Detail card section
                ScrollView {
                    VStack(spacing: 20) {
                        QualityDetailCard(quality: selectedQuality)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        
                        // Additional information
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Storage Impact", systemImage: "internaldrive")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            Text("Higher quality produces larger files. Choose based on your available storage and intended use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Quick comparison
                            VStack(alignment: .leading, spacing: 8) {
                                QualityComparisonRow(
                                    quality: .typeHigh,
                                    isSelected: selectedQuality == .typeHigh
                                )
                                QualityComparisonRow(
                                    quality: .typeMedium,
                                    isSelected: selectedQuality == .typeMedium
                                )
                                QualityComparisonRow(
                                    quality: .typeLow,
                                    isSelected: selectedQuality == .typeLow
                                )
                                QualityComparisonRow(
                                    quality: .type640x480,
                                    isSelected: selectedQuality == .type640x480
                                )
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Video Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save preference
                        UserDefaults.standard.set(selectedQuality.rawValue, forKey: "selectedVideoQuality")
                        Haptics.light()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedQuality)
    }
    
    private func qualityShortName(for quality: UIImagePickerController.QualityType) -> String {
        switch quality {
        case .typeHigh: return "High"
        case .typeMedium: return "Med"
        case .typeLow: return "Low"
        case .type640x480: return "SD"
        default: return "High"
        }
    }
}
