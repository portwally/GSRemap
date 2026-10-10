import CoreGraphics
import CoreText
import Foundation

extension AppleIIFormats {
    /// Builds the 7 x 8 character set for text screen captures from an Apple II bitmap-style
    /// font (Print Char 21), drawn at 8 points so one font unit lands on one pixel.
    @discardableResult
    public static func loadTextGlyphs(fontURL: URL) -> Bool {
        guard let provider = CGDataProvider(url: fontURL as CFURL), let cgFont = CGFont(provider) else { return false }
        let font = CTFontCreateWithGraphicsFont(cgFont, 8, nil, nil)
        var glyphs: [[UInt8]] = []
        for code in 0x20...0x7E {
            var pixels = [UInt8](repeating: 0, count: 7 * 8)
            pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 7, height: 8, bitsPerComponent: 8,
                                              bytesPerRow: 7, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
                context.setShouldAntialias(false)
                context.setFillColor(gray: 1, alpha: 1)
                var character = [UniChar(code)]
                var glyph = [CGGlyph(0)]
                guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return }
                var position = [CGPoint(x: 0, y: 1)]
                CTFontDrawGlyphs(font, &glyph, &position, 1, context)
            }
            glyphs.append((0..<8).map { row in
                (0..<7).reduce(UInt8(0)) { $0 | (pixels[row * 7 + $1] > 127 ? 0x40 >> UInt8($1) : 0) }
            })
        }
        // A font that drew nothing is no use.
        guard glyphs[0x41 - 0x20].contains(where: { $0 != 0 }) else { return false }
        textGlyphs = glyphs
        return true
    }
}
