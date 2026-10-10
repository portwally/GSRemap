import Foundation

/// Maps a target colour to the pair of pattern bytes (even row, odd row) that best
/// approximates it with a given palette. Port of 02/7A19, 7842, 74C8 and 7601.
public struct PatternTable {
    public let entryCount: Int
    public let pattern: Bool
    /// Palette entries, `$0RGB` with the reserved flag still set where it applies.
    public let palette: [UInt16]

    private var avgR: [Int] = []
    private var avgG: [Int] = []
    private var avgB: [Int] = []
    /// Spread penalty per candidate, or -1 when the candidate uses a reserved slot.
    private var penalty: [Int] = []
    /// The output byte each candidate stands for (closest match replicates one colour).
    private var bytes: [UInt8] = []

    public init(palette: [UInt16], pattern: Bool) {
        self.palette = palette
        self.entryCount = palette.count
        self.pattern = pattern
        build()
    }

    private mutating func add(_ indices: [Int], byte: UInt8) {
        let n = indices.count
        var sr = 0, sg = 0, sb = 0
        var disabled = false
        for i in indices {
            let c = palette[i]
            if c & 0x8000 != 0 { disabled = true }
            sr += ColorMath.intensity[ColorMath.red(c)]
            sg += ColorMath.intensity[ColorMath.green(c)]
            sb += ColorMath.intensity[ColorMath.blue(c)]
        }
        let r = PatternTable.divide(sr, n), g = PatternTable.divide(sg, n), b = PatternTable.divide(sb, n)
        var spread = 0
        for i in indices {
            let c = palette[i]
            spread += 3 * abs(ColorMath.intensity[ColorMath.red(c)] - r)
            spread += 4 * abs(ColorMath.intensity[ColorMath.green(c)] - g)
            spread += 2 * abs(ColorMath.intensity[ColorMath.blue(c)] - b)
        }
        avgR.append(r)
        avgG.append(g)
        avgB.append(b)
        penalty.append(disabled ? -1 : PatternTable.divide(spread, n))
        bytes.append(byte)
    }

    /// Truncating divide that never rounds a non-zero sum down to zero (02/77F7).
    private static func divide(_ sum: Int, _ n: Int) -> Int {
        let q = sum / n
        return q == 0 && sum != 0 ? 1 : q
    }

    private mutating func build() {
        switch (entryCount, pattern) {
        case (16, true):
            for i in 0..<256 { add([i >> 4, i & 15], byte: UInt8(i)) }
        case (4, true):
            for i in 0..<256 { add([i >> 6, (i >> 4) & 3, (i >> 2) & 3, i & 3], byte: UInt8(i)) }
        case (8, true):
            for i in 0..<256 { add([i >> 6, ((i >> 4) & 3) + 4, (i >> 2) & 3, (i & 3) + 4], byte: UInt8(i)) }
        case (8, false):
            for i in 0..<16 { add([i >> 2, (i & 3) + 4], byte: UInt8((i << 4) | i)) }
        case (4, false):
            for i in 0..<4 { add([i], byte: UInt8(i * 0x55)) }
        default:
            for i in 0..<entryCount { add([i], byte: UInt8((i << 4) | i)) }
        }
    }

    /// Index of the best candidate for a target given in intensity units (02/74C8).
    private func best(_ r: Int, _ g: Int, _ b: Int) -> Int {
        var bestIndex = 0, bestScore = 0x7D00
        var i = penalty.count - 1
        while i >= 0 {
            if penalty[i] >= 0 {
                let score = 3 * abs(avgR[i] - r) + 4 * abs(avgG[i] - g) + 2 * abs(avgB[i] - b) + (penalty[i] >> 4)
                if score < bestScore {
                    bestScore = score
                    bestIndex = i
                }
            }
            i -= 1
        }
        return bestIndex
    }

    /// Pattern bytes for a target in intensity units (0…255 per channel).
    public func lookup(r: Int, g: Int, b: Int) -> (even: UInt8, odd: UInt8) {
        let first = best(r, g, b)
        if !pattern { return (bytes[first], bytes[first]) }
        let r2 = min(255, max(0, 2 * r - avgR[first]))
        let g2 = min(255, max(0, 2 * g - avgG[first]))
        let b2 = min(255, max(0, 2 * b - avgB[first]))
        let second = best(r2, g2, b2)
        func swapped(_ v: Int) -> UInt8 { UInt8(((v << 4) | (v >> 4)) & 0xFF) }
        if second > first { return (UInt8(second), swapped(first)) }
        return (UInt8(first), swapped(second))
    }

    /// Pattern bytes for a 12-bit colour.
    public func lookup(colour c: Color12) -> (even: UInt8, odd: UInt8) {
        lookup(r: ColorMath.intensity[ColorMath.red(c)],
               g: ColorMath.intensity[ColorMath.green(c)],
               b: ColorMath.intensity[ColorMath.blue(c)])
    }

    /// Intensity of the palette colour a pattern byte puts at column `x`.
    public func greyIntensity(byte: UInt8, column x: Int) -> Int {
        ColorMath.intensity[ColorMath.green(palette[paletteSlot(byte: byte, column: x)])]
    }

    /// Pixel value (0…15 or 0…3) a pattern byte gives at column `x`.
    @inline(__always) public func pixel(byte: UInt8, column x: Int) -> UInt8 {
        if entryCount == 16 { return x & 1 == 0 ? byte >> 4 : byte & 15 }
        return (byte >> UInt8(6 - 2 * (x & 3))) & 3
    }

    /// Prototype slot behind the pixel at column `x`.
    @inline(__always) public func paletteSlot(byte: UInt8, column x: Int) -> Int {
        let v = Int(pixel(byte: byte, column: x))
        return entryCount == 8 && x & 1 == 1 ? v + 4 : v
    }
}
