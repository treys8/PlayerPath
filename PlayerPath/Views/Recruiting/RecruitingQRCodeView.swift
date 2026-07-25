//
//  RecruitingQRCodeView.swift
//  PlayerPath
//
//  Full-screen QR for the athlete's public profile link — built for in-person
//  moments (showcase, tournament, camp): hand the phone over, the coach scans,
//  the film opens in their browser.
//
//  Encodes the clean share URL, nothing else — whatever scans this must land on
//  exactly the link a coach would have been emailed.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct RecruitingQRCodeView: View {
    let athleteName: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let qrImage {
                    Image(uiImage: qrImage)
                        // The CGImage is upscaled without smoothing; .none here
                        // keeps SwiftUI from re-blurring the crisp modules.
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(20)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                } else {
                    // CIFilter failing on a static string doesn't happen in
                    // practice, but a blank sheet with no explanation is worse
                    // than a fallback the athlete can still act on.
                    Text(url.absoluteString)
                        .font(.bodyMedium)
                        .textSelection(.enabled)
                        .padding()
                }

                VStack(spacing: 6) {
                    Text(athleteName)
                        .font(.headingLarge)
                    Text("Scan to watch game film")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .navigationTitle("Profile QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ppAccent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// QR at native module resolution, upscaled 12× so it renders sharp at any
    /// screen size. Black-on-white deliberately — dark mode inverts UI colors,
    /// but scanners want maximum contrast and quiet-zone convention.
    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
