import Foundation

/// Fills in the "calculate" slots of a prototype from an image's colour histogram.
/// Port of the routine at 02/6FF4: popularity with neighbourhood suppression.
public enum PaletteCalculator {
    static let radius = 50

    /// - Parameters:
    ///   - prototype: entries with flag bits.
    ///   - histogram: 4096 counts, one per 12-bit colour (left unchanged).
    /// - Returns: one entry per slot; reserved slots keep their `$8000` flag.
    public static func calculate(prototype: [UInt16], histogram: [UInt16]) -> [UInt16] {
        var proto = prototype
        var hist = histogram
        let count = proto.count

        // 640 dither: black and white are shared between the two half-palettes.
        if count == 8 {
            merge(&proto, 0, 4)
            merge(&proto, 3, 7)
        }

        var distinct = hist.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        var freeSlots = 0
        for e in proto {
            if e & 0x8000 != 0 { continue }
            if e & 0x4000 != 0 {
                freeSlots += 1
            } else if hist[Int(e & 0x0FFF)] != 0 {
                distinct -= 1
                hist[Int(e & 0x0FFF)] = 0
            }
        }

        var chosen: [UInt16] = []
        if freeSlots > 0 {
            if freeSlots >= distinct {
                for c in 0..<4096 where hist[c] != 0 && chosen.count < 16 { chosen.append(UInt16(c)) }
            } else {
                let peak = Int(argmax(hist).count)
                for c in 0..<4096 where hist[c] != 0 {
                    let bias = (peak >> 3) + ColorMath.distance(UInt16(c), 0x777) * peak / 9
                    hist[c] = UInt16(min(0xFFFF, Int(hist[c]) + bias))
                }
                for e in proto where e & 0xC000 == 0 { reduce(&hist, around: e) }
                var remaining = freeSlots
                while remaining > 0 && chosen.count < 16 {
                    remaining -= 1
                    let best = argmax(hist)
                    if best.count == 0 { break }
                    reduce(&hist, around: UInt16(best.index))
                    hist[best.index] = 0
                    chosen.append(UInt16(best.index))
                }
            }
        }

        // A chosen colour that equals a calculated slot's default stays in that slot.
        var k = 0
        while k < chosen.count {
            var matched = false
            for j in 0..<count where proto[j] == chosen[k] | 0x4000 {
                proto[j] = chosen[k]
                chosen[k] = chosen[chosen.count - 1]
                chosen.removeLast()
                matched = true
                break
            }
            if !matched { k += 1 }
        }

        // Remaining slots take the remaining colours, darkest first.
        var out = [UInt16](repeating: 0, count: count)
        for i in 0..<count {
            var e = proto[i]
            if e & 0xC000 == 0x4000 {
                e &= 0x0FFF
                if !chosen.isEmpty {
                    var best = 0, bestValue = 1000
                    for (n, c) in chosen.enumerated() {
                        let v = c == e ? 0 : ColorMath.brightness(c)
                        if v < bestValue {
                            bestValue = v
                            best = n
                        }
                    }
                    e = chosen[best]
                    chosen[best] = chosen[chosen.count - 1]
                    chosen.removeLast()
                }
            }
            out[i] = e
        }
        if count == 8 {
            if out[4] == 0xFFFF { out[4] = out[0] }
            if out[7] == 0xFFFF { out[7] = out[3] }
        }
        return out
    }

    private static func merge(_ p: inout [UInt16], _ a: Int, _ b: Int) {
        let fa = p[a] & 0xC000, fb = p[b] & 0xC000
        if fa == 0 && fb == 0x4000 {
            p[b] = p[a]
        } else if fa == 0x4000 && fb == 0 {
            p[a] = p[b]
            p[b] = 0xFFFF
        } else if fa == 0x4000 && fb == 0x4000 {
            p[b] = 0xFFFF
        }
    }

    private static func argmax(_ hist: [UInt16]) -> (index: Int, count: UInt16) {
        var best = 0
        var peak: UInt16 = 0
        for c in 0..<4096 where hist[c] > peak {
            peak = hist[c]
            best = c
        }
        return (best, peak)
    }

    /// Scales down the counts of colours close to `colour` (02/6E4B).
    private static func reduce(_ hist: inout [UInt16], around colour: UInt16) {
        for c in 0..<4096 where hist[c] != 0 {
            let d = ColorMath.distance(UInt16(c), colour & 0x0FFF)
            if d < radius {
                hist[c] = UInt16(max(1, Int(hist[c]) * d / radius))
            }
        }
    }
}
