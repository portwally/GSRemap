import Foundation

/// A Super Hi-Res "screen image": what the IIgs can display directly.
/// Pixels are stored unpacked, one palette index per pixel.
public struct ScreenImage {
    /// Width in pixels of the image's own mode (320 or 640 for one screen).
    public var width: Int
    public var height: Int
    /// Master mode: true when the image is 640-mode.
    public var is640: Bool
    /// One scan-line control byte per line: low nibble = palette, bit 7 = 640 mode.
    public var scbs: [UInt8]
    /// Colour tables, 16 entries each. Normally 1…16 tables; 200 for "3200 colour" pictures.
    public var palettes: [[Color12]]
    /// Row-major pixel values: 0…15 in 320 mode, 0…3 in 640 mode.
    public var pixels: [UInt8]

    public static let standard320: [Color12] = [
        0x000, 0x777, 0x841, 0x72C, 0x00F, 0x080, 0xF70, 0xD00,
        0xFA9, 0xFF0, 0x0E0, 0x4DF, 0xDAF, 0x78F, 0xCCC, 0xFFF,
    ]
    public static let standard640: [Color12] = [
        0x000, 0xF00, 0x0F0, 0xFFF, 0x000, 0x00F, 0xFF0, 0xFFF,
        0x000, 0xF00, 0x0F0, 0xFFF, 0x000, 0x00F, 0xFF0, 0xFFF,
    ]

    public init(width: Int, height: Int, is640: Bool, palettes: [[Color12]]? = nil) {
        self.width = width
        self.height = height
        self.is640 = is640
        self.scbs = [UInt8](repeating: is640 ? 0x80 : 0x00, count: height)
        self.palettes = palettes ?? [is640 ? ScreenImage.standard640 : ScreenImage.standard320]
        self.pixels = [UInt8](repeating: 0, count: width * height)
    }

    public var pixelsPerByte: Int { is640 ? 4 : 2 }
    public var bytesPerRow: Int { (width + pixelsPerByte - 1) / pixelsPerByte }

    /// Palette-table index a 640-mode pixel uses, by its column: 8, 12, 0, 4.
    @inline(__always) public static func offset640(column x: Int) -> Int { [8, 12, 0, 4][x & 3] }

    /// The colour shown at a pixel.
    public func colour(_ x: Int, _ y: Int) -> Color12 {
        let scb = scbs[y]
        let table = palettes[paletteIndex(line: y)]
        let v = Int(pixels[y * width + x])
        if scb & 0x80 != 0 { return table[ScreenImage.offset640(column: x) + (v & 3)] }
        return table[v & 15]
    }

    public func paletteIndex(line y: Int) -> Int {
        if palettes.count > 16 { return min(y, palettes.count - 1) }
        return min(Int(scbs[y] & 0x0F), palettes.count - 1)
    }

    /// Packs one line into SHR bytes (leftmost pixel in the high bits).
    public func packedRow(_ y: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytesPerRow)
        let base = y * width
        if is640 {
            for x in 0..<width { out[x >> 2] |= (pixels[base + x] & 3) << UInt8(6 - 2 * (x & 3)) }
        } else {
            for x in 0..<width { out[x >> 1] |= (pixels[base + x] & 15) << UInt8(x & 1 == 0 ? 4 : 0) }
        }
        return out
    }

    /// Unpacks SHR bytes into one line.
    public mutating func setPackedRow(_ y: Int, _ bytes: [UInt8]) {
        let base = y * width
        if is640 {
            for x in 0..<width where x >> 2 < bytes.count {
                pixels[base + x] = (bytes[x >> 2] >> UInt8(6 - 2 * (x & 3))) & 3
            }
        } else {
            for x in 0..<width where x >> 1 < bytes.count {
                pixels[base + x] = (bytes[x >> 1] >> UInt8(x & 1 == 0 ? 4 : 0)) & 15
            }
        }
    }

    /// RGBA bytes at 640 × (2·height) for 640 mode, or (2·width) × (2·height) for 320 mode,
    /// so both modes come out with the right shape on square pixels.
    public func rgba() -> (width: Int, height: Int, bytes: [UInt8]) {
        let xRep = is640 ? 1 : 2
        let outW = width * xRep, outH = height * 2
        var out = [UInt8](repeating: 255, count: outW * outH * 4)
        for y in 0..<height {
            var d = (y * 2) * outW * 4
            for x in 0..<width {
                let (r, g, b) = ColorMath.rgb8(colour(x, y))
                for _ in 0..<xRep {
                    out[d] = r
                    out[d + 1] = g
                    out[d + 2] = b
                    d += 4
                }
            }
            let rowStart = (y * 2) * outW * 4
            let next = rowStart + outW * 4
            out.replaceSubrange(next..<(next + outW * 4), with: out[rowStart..<next])
        }
        return (outW, outH, out)
    }

    /// Screen → true colour ("exact" conversion): one true-colour pixel per screen pixel.
    public func toTrueColor() -> TrueColorImage {
        var img = TrueColorImage(width: width, height: height, tallPixels: is640)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = ColorMath.rgb8(colour(x, y))
                img.setPixel(x, y, r, g, b)
            }
        }
        return img
    }
}
