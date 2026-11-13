import Foundation

struct TalkingPoint: Identifiable, Equatable {
    let id: Int
    let text: String
    var isCovered = false
}

/// The loudness of a buffer, 0…1: 0 at −60 dB and below, 1 at 0 dB.
func level(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let meanSquare = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
    guard meanSquare > 0 else { return 0 }
    let db = 10 * log10(meanSquare)
    return min(max((db + 60) / 60, 0), 1)
}
