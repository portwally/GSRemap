import Foundation

/// SuperConvert's "true color image": more colours or pixels than the IIgs can show.
/// The original keeps 15-bit colour (or 8-bit grey); this port keeps 8 bits per channel.
public struct TrueColorImage {
    public var width: Int
    public var height: Int
    /// RGB triplets, row-major, `width * height * 3` bytes.
    public var rgb: [UInt8]
    /// True when pixels are 640-mode shaped (half as wide as tall).
    public var tallPixels: Bool

    public init(width: Int, height: Int, rgb: [UInt8]? = nil, tallPixels: Bool = false) {
        self.width = width
        self.height = height
        self.rgb = rgb ?? [UInt8](repeating: 0, count: width * height * 3)
        self.tallPixels = tallPixels
    }

    @inline(__always) public func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 3
        return (rgb[i], rgb[i + 1], rgb[i + 2])
    }

    @inline(__always) public mutating func setPixel(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        let i = (y * width + x) * 3
        rgb[i] = r
        rgb[i + 1] = g
        rgb[i + 2] = b
    }

    /// Number of distinct 12-bit colours, and whether every pixel is grey.
    public func colourStatistics() -> (distinct: Int, isGrey: Bool, isBlackAndWhite: Bool) {
        var seen = [Bool](repeating: false, count: 4096)
        var distinct = 0
        var grey = true
        var bw = true
        var i = 0
        while i < rgb.count {
            let r = Int(rgb[i]) >> 4, g = Int(rgb[i + 1]) >> 4, b = Int(rgb[i + 2]) >> 4
            let c = r << 8 | g << 4 | b
            if !seen[c] {
                seen[c] = true
                distinct += 1
                if r != g || g != b { grey = false }
                if c != 0 && c != 0xFFF { bw = false }
            }
            i += 3
        }
        return (distinct, grey, bw)
    }

    /// RGBA bytes for display.
    public func rgba() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        var s = 0, d = 0
        while s < rgb.count {
            out[d] = rgb[s]
            out[d + 1] = rgb[s + 1]
            out[d + 2] = rgb[s + 2]
            s += 3
            d += 4
        }
        return out
    }
}

extension TrueColorImage {
    /// The top-left `width` x `height` part of the image.
    public func cropped(width w: Int, height h: Int) -> TrueColorImage {
        let w = min(w, width), h = min(h, height)
        var out = TrueColorImage(width: w, height: h, tallPixels: tallPixels)
        for y in 0..<h {
            let s = y * width * 3
            out.rgb.replaceSubrange((y * w * 3)..<((y + 1) * w * 3), with: rgb[s..<(s + w * 3)])
        }
        return out
    }

    /// Rotate/flip, with the original's option bits: 1 = mirror, 2 = flip, 4 = transpose.
    public func transformed(_ bits: Int) -> TrueColorImage {
        var image = self
        if bits & 1 != 0 {
            for y in 0..<height {
                for x in 0..<(width / 2) {
                    let a = image.pixel(x, y), b = image.pixel(width - 1 - x, y)
                    image.setPixel(x, y, b.r, b.g, b.b)
                    image.setPixel(width - 1 - x, y, a.r, a.g, a.b)
                }
            }
        }
        if bits & 2 != 0 {
            for y in 0..<(height / 2) {
                for x in 0..<width {
                    let a = image.pixel(x, y), b = image.pixel(x, height - 1 - y)
                    image.setPixel(x, y, b.r, b.g, b.b)
                    image.setPixel(x, height - 1 - y, a.r, a.g, a.b)
                }
            }
        }
        if bits & 4 != 0 {
            var turned = TrueColorImage(width: height, height: width, tallPixels: false)
            for y in 0..<height {
                for x in 0..<width {
                    let p = image.pixel(x, y)
                    turned.setPixel(y, x, p.r, p.g, p.b)
                }
            }
            image = turned
        }
        return image
    }
}
