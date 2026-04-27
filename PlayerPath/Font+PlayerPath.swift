//
//  Font+PlayerPath.swift
//  PlayerPath
//
//  Custom font tokens. Use `.font(.ppHeadline)` etc. instead of raw PostScript names.
//

import SwiftUI

extension Font {

    // MARK: - Display / Headlines (Fraunces — serif)

    static func ppDisplay(_ size: CGFloat) -> Font {
        .custom("Fraunces72pt-Bold", size: size, relativeTo: .largeTitle)
    }

    static let ppLargeTitle = Font.custom("Fraunces72pt-Bold", size: 34, relativeTo: .largeTitle)
    static let ppTitle      = Font.custom("Fraunces72pt-SemiBold", size: 28, relativeTo: .title)
    static let ppTitle2     = Font.custom("Fraunces72pt-SemiBold", size: 22, relativeTo: .title2)
    static let ppTitle3     = Font.custom("Fraunces72pt-Regular", size: 20, relativeTo: .title3)

    // MARK: - Body / UI (Inter — sans)

    static let ppHeadline   = Font.custom("Inter18pt-SemiBold", size: 17, relativeTo: .headline)
    static let ppBody       = Font.custom("Inter18pt-Regular",  size: 17, relativeTo: .body)
    static let ppBodyBold   = Font.custom("Inter18pt-Bold",     size: 17, relativeTo: .body)
    static let ppCallout    = Font.custom("Inter18pt-Medium",   size: 16, relativeTo: .callout)
    static let ppSubheadline = Font.custom("Inter18pt-Medium",  size: 15, relativeTo: .subheadline)
    static let ppFootnote   = Font.custom("Inter18pt-Regular",  size: 13, relativeTo: .footnote)
    static let ppCaption    = Font.custom("Inter18pt-Regular",  size: 12, relativeTo: .caption)
    static let ppCaptionBold = Font.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption)

    // MARK: - Stats / Numerics (Archivo — geometric, condensed for scoreboard feel)

    static func ppStat(_ size: CGFloat) -> Font {
        .custom("ArchivoCondensed-Black", size: size, relativeTo: .largeTitle)
    }

    static let ppStatLarge  = Font.custom("ArchivoCondensed-Black", size: 44, relativeTo: .largeTitle)
    static let ppStatMedium = Font.custom("ArchivoCondensed-Bold",  size: 28, relativeTo: .title)
    static let ppStatSmall  = Font.custom("Archivo-Bold",            size: 17, relativeTo: .headline)
}
