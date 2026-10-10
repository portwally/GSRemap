import Foundation

/// The computer-independent load formats that macOS doesn't already read.
public enum IndependentFormats {
    /// CompuServe RLE (original loader at 06/ADD4). Plain 7-bit text that may sit anywhere
    /// in the file: ESC "G" then "H" (256 x 192) or "M" (128 x 96), followed by characters
    /// whose value minus 32 is a run length, alternating black and white.
    public static func loadRLE(_ d: [UInt8]) throws -> ScreenImage {
        let text = d.map { $0 & 0x7F }
        var i = 0
        var start = -1
        while i + 2 < text.count {
            if text[i] == 0x1B && text[i + 1] == 0x47 {
                start = i + 2
                break
            }
            i += 1
        }
        guard start >= 0 else { throw FormatError.notThisFormat("a CompuServe RLE picture") }
        let high = text[start] == 0x48
        let width = high ? 256 : 128, height = high ? 192 : 96
        var screen = ScreenImage(width: width, height: height, is640: false)
        var at = 0
        var colour: UInt8 = 0
        i = start + 1
        while i < text.count && at < screen.pixels.count {
            let c = text[i]
            i += 1
            if c == 0x1B { break }          // ESC "G" "N" ends the picture
            if c < 0x20 { continue }        // line breaks from a capture buffer
            let run = min(Int(c) - 32, screen.pixels.count - at)
            for _ in 0..<run {
                screen.pixels[at] = colour
                at += 1
            }
            colour ^= 15
        }
        return screen
    }

    /// IPI image (original loader at 05/5A5A): three files ending .R, .G and .B, each a
    /// square of 8-bit samples, 256 or 512 on a side. Any one of the three may be picked.
    public static func loadIPI(_ url: URL) throws -> TrueColorImage {
        let ending = url.pathExtension
        guard ["r", "g", "b"].contains(ending.lowercased()) else {
            throw FormatError.unsupported("IPI images are three files ending in .R, .G and .B. Pick any one of them.")
        }
        let base = url.deletingPathExtension()
        func plane(_ letter: String) throws -> [UInt8] {
            let sameCase = ending == ending.uppercased() ? letter.uppercased() : letter.lowercased()
            for candidate in [sameCase, letter.uppercased(), letter.lowercased()] {
                if let data = try? Data(contentsOf: base.appendingPathExtension(candidate)) { return [UInt8](data) }
            }
            throw FormatError.unsupported("Can't find the .\(letter.uppercased()) file that goes with \(url.lastPathComponent).")
        }
        let r = try plane("r"), g = try plane("g"), b = try plane("b")
        let side = r.count >= 262144 ? 512 : 256
        guard min(r.count, g.count, b.count) >= side * side else {
            throw FormatError.notThisFormat("an IPI image (256 x 256 or 512 x 512)")
        }
        var image = TrueColorImage(width: side, height: side)
        for i in 0..<(side * side) {
            image.rgb[i * 3] = r[i]
            image.rgb[i * 3 + 1] = g[i]
            image.rgb[i * 3 + 2] = b[i]
        }
        return image
    }

    /// QuickRayTracer raw image (original loader at 05/5C9B): width and height words, then
    /// for each line its number followed by a row of reds, a row of greens and a row of blues.
    public static func loadQRT(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count >= 6 else { throw FormatError.notThisFormat("a QRT raw image file") }
        let width = word(d, 0), height = word(d, 2)
        guard width > 0, height > 0, width <= 8192, height <= 8192 else {
            throw FormatError.notThisFormat("a QRT raw image file")
        }
        var image = TrueColorImage(width: width, height: height)
        var i = 4
        while i + 2 + 3 * width <= d.count {
            let line = word(d, i)
            i += 2
            if line < height {
                for x in 0..<width { image.setPixel(x, line, d[i + x], d[i + width + x], d[i + 2 * width + x]) }
            }
            i += 3 * width
        }
        return image
    }
}
