//
//  PhotoCameraLayout.swift
//  PlayerPath
//
//  Full-bleed preview with floating chrome — the pattern used by Instagram,
//  Snapchat, Google Photos, and most modern third-party cameras.
//
//  No chrome bars, no aspect reshaping of the preview, no letterbox/pillarbox
//  games. The preview fills the screen using `.resizeAspect` so the full
//  sensor frame is always visible (black strips at the short edges in each
//  orientation — that's the photo boundary, same as native Camera). Controls
//  float over the preview with subtle dark backgrounds for legibility.
//
//  Positions adapt to portrait/landscape via `GeometryReader` — in portrait,
//  shutter sits at the bottom; in landscape it moves to the right edge
//  (user's thumb position on a sideways phone).
//

import SwiftUI
import AVFoundation

struct PhotoCameraLayout: View {
    @ObservedObject var viewModel: PhotoCameraViewModel
    let landscape: Bool
    let lastThumbnail: UIImage?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            PhotoCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()
                .opacity(viewModel.isSessionReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isSessionReady)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            viewModel.handleTapToFocus(atLayerPoint: value.location)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            viewModel.handlePinch(scale: value.magnification)
                        }
                        .onEnded { _ in
                            viewModel.endPinch()
                        }
                )

            if let focusPoint = viewModel.lastFocusPoint {
                PhotoFocusReticle(point: focusPoint)
                    .id("\(focusPoint.x),\(focusPoint.y)")
            }

            if landscape {
                landscapeControls
            } else {
                portraitControls
            }
        }
    }

    // MARK: - Portrait Controls

    private var portraitControls: some View {
        VStack(spacing: 0) {
            // Top: cancel left, flash right
            HStack {
                PhotoCancelButton(action: onCancel)
                Spacer()
                PhotoFlashButton(viewModel: viewModel)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            // Bottom: zoom pills + shutter row
            VStack(spacing: 18) {
                PhotoZoomPicker(viewModel: viewModel)

                ZStack {
                    PhotoShutterButton(viewModel: viewModel)

                    HStack {
                        PhotoLastThumbnail(image: lastThumbnail)
                        Spacer()
                        PhotoFlipButton(viewModel: viewModel)
                    }
                    .padding(.horizontal, 36)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Landscape Controls

    private var landscapeControls: some View {
        HStack(spacing: 0) {
            // Left: cancel + flash clustered at top (matches portrait's top bar).
            VStack(spacing: 12) {
                PhotoCancelButton(action: onCancel)
                PhotoFlashButton(viewModel: viewModel)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Spacer()

            // Right: vertical zoom pills + shutter column
            HStack(spacing: 18) {
                PhotoZoomPicker(viewModel: viewModel, vertical: true)

                ZStack {
                    PhotoShutterButton(viewModel: viewModel)

                    VStack {
                        PhotoLastThumbnail(image: lastThumbnail)
                        Spacer()
                        PhotoFlipButton(viewModel: viewModel)
                    }
                    .padding(.vertical, 36)
                }
            }
            .padding(.trailing, 24)
            .padding(.vertical, 16)
        }
    }
}
