import Foundation

/// The True Color menu's filters (original code in the SUPERFX segment, 0A/0000 onward).
/// The original works on 5-bit channels; the same arithmetic is applied here to 8-bit ones.
public enum Filters {
    /// Runs `body` on every pixel with its 3 x 3 neighbourhood (edges repeat), one channel at a time.
    /// Neighbours are numbered 0…8 left to right, top to bottom; 4 is the pixel itself.
    static func neighbourhood(_ image: TrueColorImage, _ body: ([Int]) -> Int) -> TrueColorImage {
        var out = image
        let w = image.width, h = image.height
        var n = [Int](repeating: 0, count: 9)
        image.rgb.withUnsafeBufferPointer { src in
            for y in 0..<h {
                let rows = [max(0, y - 1), y, min(h - 1, y + 1)]
                for x in 0..<w {
                    let cols = [max(0, x - 1), x, min(w - 1, x + 1)]
                    for c in 0..<3 {
                        for j in 0..<3 {
                            for i in 0..<3 { n[j * 3 + i] = Int(src[(rows[j] * w + cols[i]) * 3 + c]) }
                        }
                        out.rgb[(y * w + x) * 3 + c] = UInt8(min(255, max(0, body(n))))
                    }
                }
            }
        }
        return out
    }

    public static func median(_ image: TrueColorImage) -> TrueColorImage {
        neighbourhood(image) { $0.sorted()[4] }
    }

    /// In the original the acceptance window is wider than the whole value range, so every
    /// neighbour counts and the result is the plain average. The port does the same.
    public static func sigma(_ image: TrueColorImage) -> TrueColorImage {
        neighbourhood(image) { ($0.reduce(0, +) + 4) / 9 }
    }

    public static func emboss(_ image: TrueColorImage) -> TrueColorImage {
        neighbourhood(image) { n in
            -n[0] - 2 * n[1] - 2 * n[3] + 2 * n[5] + 2 * n[7] + n[8] + 128
        }
    }

    /// `factor` 0…99: larger blurs more.
    public static func blur(_ image: TrueColorImage, factor: Int) -> TrueColorImage {
        let weight = (100 - factor) / 2 - 13
        let divisor = max(1, weight + 12)
        return neighbourhood(image) { n in
            let sum = n[0] + 2 * n[1] + n[2] + 2 * n[3] + weight * n[4] + 2 * n[5] + n[6] + 2 * n[7] + n[8]
            return (sum + divisor / 2) / divisor
        }
    }

    /// `factor` 0…99: larger sharpens more.
    public static func sharpen(_ image: TrueColorImage, factor: Int) -> TrueColorImage {
        let weight = (100 - factor) / 2 + 13
        let divisor = max(1, weight - 12)
        return neighbourhood(image) { n in
            let sum = -n[0] - 2 * n[1] - n[2] - 2 * n[3] + weight * n[4] - 2 * n[5] - n[6] - 2 * n[7] - n[8]
            return sum < 0 ? 0 : (sum + divisor / 2) / divisor
        }
    }

    public static func solarize(_ image: TrueColorImage) -> TrueColorImage {
        var out = image
        for i in 0..<out.rgb.count where out.rgb[i] > 132 { out.rgb[i] = 255 - out.rgb[i] }
        return out
    }

    /// Each pixel minus the average of its four diagonal neighbours, amplified. `factor` 0…99:
    /// smaller gives stronger edges.
    public static func findEdges(_ image: TrueColorImage, factor: Int) -> TrueColorImage {
        let gain = Double(100 - factor) / 20 + 1.5
        return neighbourhood(image) { n in
            Int((gain * (Double(n[4]) - Double(n[0] + n[2] + n[6] + n[8]) / 4)).rounded())
        }
    }

    /// Moves each pixel's brightness half-way toward (or away from) a sine-shaped S curve,
    /// keeping hue and saturation.
    public static func contrast(_ image: TrueColorImage, increase: Bool) -> TrueColorImage {
        var table = [Double](repeating: 0, count: 256)
        for v in 0..<256 {
            let x = Double(v) / 255
            let curve = (sin(Double.pi * (x - 0.5)) + 1) / 2
            table[v] = min(1, max(0, x + (increase ? 0.5 : -0.5) * (curve - x)))
        }
        var out = image
        var i = 0
        while i < out.rgb.count {
            let top = Int(max(out.rgb[i], out.rgb[i + 1], out.rgb[i + 2]))
            if top > 0 {
                let scale = table[top] * 255 / Double(top)
                for c in 0..<3 { out.rgb[i + c] = UInt8(min(255, (Double(out.rgb[i + c]) * scale).rounded())) }
            } else {
                let v = UInt8((table[0] * 255).rounded())
                for c in 0..<3 { out.rgb[i + c] = v }
            }
            i += 3
        }
        return out
    }

    /// Spreads brightness levels so each is used about equally; colours keep their hue.
    public static func equalize(_ image: TrueColorImage) -> TrueColorImage {
        var histogram = [Int](repeating: 0, count: 256)
        var i = 0
        while i < image.rgb.count {
            histogram[ColorMath.grey(Int(image.rgb[i]), Int(image.rgb[i + 1]), Int(image.rgb[i + 2]))] += 1
            i += 3
        }
        let total = image.width * image.height
        guard let lowest = histogram.first(where: { $0 > 0 }), total > lowest else { return image }
        var map = [Int](repeating: 0, count: 256)
        var running = 0
        for v in 0..<256 {
            running += histogram[v]
            map[v] = max(0, (running - lowest) * 255 / (total - lowest))
        }
        var out = image
        i = 0
        while i < out.rgb.count {
            let grey = ColorMath.grey(Int(out.rgb[i]), Int(out.rgb[i + 1]), Int(out.rgb[i + 2]))
            let target = map[grey]
            for c in 0..<3 {
                let v = grey == 0 ? target : Int(out.rgb[i + c]) * target / grey
                out.rgb[i + c] = UInt8(min(255, v))
            }
            i += 3
        }
        return out
    }
}
