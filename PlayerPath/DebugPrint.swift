//
//  DebugPrint.swift
//  PlayerPath
//
//  Silences all print() calls in Release builds to prevent
//  debug output from leaking to production and improve performance.
//

#if !DEBUG
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // No-op in Release builds
}
#endif
