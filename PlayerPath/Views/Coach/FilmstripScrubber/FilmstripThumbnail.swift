//
//  FilmstripThumbnail.swift
//  PlayerPath
//
//  Model for a single frame in the filmstrip scrubber timeline.
//

import UIKit

struct FilmstripThumbnail: Identifiable {
    let id: Int          // Frame index (0-based)
    let timestamp: Double // Seconds into the video
    var image: UIImage?   // nil while generating
}
