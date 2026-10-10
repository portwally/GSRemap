import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG, PNG, GIF, TIFF, BMP and anything else macOS can decode.
/// (The original carried its own JPEG, PNG and GIF code; ImageIO replaces it here.)
public enum ModernImage {
    public static func load(_ url: URL) throws -> TrueColorImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FormatError.notThisFormat("a picture macOS can read")
        }
        return try trueColor(from: image)
    }

    public static func trueColor(from image: CGImage) throws -> TrueColorImage {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw FormatError.unsupported("Not enough memory to decode this picture.") }
        var out = TrueColorImage(width: w, height: h)
        var s = 0, d = 0
        while s < rgba.count {
            out.rgb[d] = rgba[s]
            out.rgb[d + 1] = rgba[s + 1]
            out.rgb[d + 2] = rgba[s + 2]
            s += 4
            d += 3
        }
        return out
    }

    public static func cgImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func cgImage(_ screen: ScreenImage) -> CGImage? {
        let r = screen.rgba()
        return cgImage(width: r.width, height: r.height, rgba: r.bytes)
    }

    public static func cgImage(_ image: TrueColorImage) -> CGImage? {
        cgImage(width: image.width, height: image.height, rgba: image.rgba())
    }

    public static func save(_ image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw FormatError.unsupported("Can't create \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FormatError.unsupported("Can't write \(url.lastPathComponent).")
        }
    }
}
