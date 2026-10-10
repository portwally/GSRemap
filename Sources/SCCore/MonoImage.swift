import Foundation

/// SuperConvert's third image type: one bit per pixel.
public struct MonoImage: Equatable {
    public var width: Int
    public var height: Int
    /// Row-major, 1 = white, 0 = black.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, white: Bool = true) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: white ? 1 : 0, count: width * height)
    }

    public var whiteCount: Int { pixels.reduce(0) { $0 + Int($1) } }

    public mutating func negate() {
        for i in 0..<pixels.count { pixels[i] ^= 1 }
    }

    public func rgba() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<pixels.count where pixels[i] == 0 {
            out[i * 4] = 0
            out[i * 4 + 1] = 0
            out[i * 4 + 2] = 0
        }
        return out
    }
}

public enum MonoRendering: Int, CaseIterable {
    case errorDiffusion, patternDither, halftone, threshold

    public var title: String {
        switch self {
        case .errorDiffusion: return "Error diffusion"
        case .patternDither: return "Pattern dither"
        case .halftone: return "Halftone"
        case .threshold: return "50% threshold"
        }
    }
}

public enum MonoAspect: Int, CaseIterable {
    case square, tall, wide

    public var title: String { ["Square", "Tall", "Wide"][rawValue] }
}

public enum MonoShrink: Int, CaseIterable {
    case grayscale, threshold, lineArtOnWhite, lineArtOnBlack

    public var title: String {
        switch self {
        case .grayscale: return "Grayscale"
        case .threshold: return "Black & white (50% threshold)"
        case .lineArtOnWhite: return "B&W (line art on white background)"
        case .lineArtOnBlack: return "B&W (line art on black background)"
        }
    }
}

public struct FromMonoOptions {
    public var mode640 = true
    public var aspect = MonoAspect.tall
    /// 1, 2 or 4: how many monochrome pixels become one, each way.
    public var scaling = 1
    public var shrink = MonoShrink.grayscale

    public init() {}

    /// How often each resulting pixel is repeated across and down.
    public var repeats: (x: Int, y: Int) {
        switch aspect {
        case .square: return (mode640 ? 2 : 1, 1)
        case .tall: return (1, mode640 ? 1 : 2)
        case .wide: return (mode640 ? 4 : 2, 1)
        }
    }

    public func resultSize(of image: MonoImage) -> (width: Int, height: Int) {
        (max(1, image.width / scaling) * repeats.x, max(1, image.height / scaling) * repeats.y)
    }
}

/// Conversions to and from monochrome images. The original's rendering patterns were not
/// traced; standard dither and halftone screens are used.
public enum MonoConversion {
    static let bayer: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    /// A clustered-dot screen: thresholds grow outward from the centre of each 4 x 4 cell.
    static let cluster: [Int] = [12, 5, 6, 13, 4, 0, 1, 7, 11, 3, 2, 8, 15, 10, 9, 14]

    /// Renders a grid of grey levels (0…255) as black and white.
    static func render(width: Int, height: Int, method: MonoRendering, grey: (Int, Int) -> Int) -> MonoImage {
        var out = MonoImage(width: width, height: height)
        switch method {
        case .threshold:
            for y in 0..<height { for x in 0..<width { out.pixels[y * width + x] = grey(x, y) >= 128 ? 1 : 0 } }
        case .patternDither, .halftone:
            let screen = method == .halftone ? cluster : bayer
            for y in 0..<height {
                for x in 0..<width {
                    let level = (screen[(y & 3) * 4 + (x & 3)] * 255 + 127) / 16 + 8
                    out.pixels[y * width + x] = grey(x, y) >= level ? 1 : 0
                }
            }
        case .errorDiffusion:
            var current = [Int](repeating: 0, count: width + 2), next = current
            for y in 0..<height {
                let forward = y & 1 == 0
                var x = forward ? 0 : width - 1
                let step = forward ? 1 : -1
                for _ in 0..<width {
                    let wanted = grey(x, y) + ((current[x + 1] + 8) >> 4)
                    let white = wanted >= 128
                    out.pixels[y * width + x] = white ? 1 : 0
                    let error = wanted - (white ? 255 : 0)
                    current[x + 1 + step] += error * 7
                    next[x + 1 - step] += error * 3
                    next[x + 1] += error * 5
                    next[x + 1 + step] += error
                    x += step
                }
                swap(&current, &next)
                for k in 0..<next.count { next[k] = 0 }
            }
        }
        return out
    }

    /// True colour → monochrome, optionally 2 or 4 times larger each way.
    public static func monochrome(from image: TrueColorImage, xScale: Int, yScale: Int,
                                  method: MonoRendering) -> MonoImage {
        render(width: image.width * xScale, height: image.height * yScale, method: method) { x, y in
            let p = image.pixel(x / xScale, y / yScale)
            return ColorMath.grey(Int(p.r), Int(p.g), Int(p.b))
        }
    }

    /// Screen → monochrome, optionally 2 or 4 times larger each way.
    public static func monochrome(from screen: ScreenImage, xScale: Int, yScale: Int,
                                  method: MonoRendering) -> MonoImage {
        monochrome(from: screen.toTrueColor(), xScale: xScale, yScale: yScale, method: method)
    }

    /// Reduces the image by `options.scaling`, giving a grey level 0…255 per resulting pixel.
    static func reduce(_ image: MonoImage, _ options: FromMonoOptions) -> (width: Int, height: Int, grey: [Int]) {
        let n = options.scaling
        let w = max(1, image.width / n), h = max(1, image.height / n)
        var grey = [Int](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var white = 0, count = 0
                for sy in (y * n)..<min(image.height, y * n + n) {
                    for sx in (x * n)..<min(image.width, x * n + n) {
                        white += Int(image.pixels[sy * image.width + sx])
                        count += 1
                    }
                }
                let value: Int
                switch n == 1 ? MonoShrink.threshold : options.shrink {
                case .grayscale: value = white * 255 / max(1, count)
                case .threshold: value = white * 2 > count || (n == 1 && white == 1) ? 255 : 0
                case .lineArtOnWhite: value = white == count ? 255 : 0
                case .lineArtOnBlack: value = white > 0 ? 255 : 0
                }
                grey[y * w + x] = value
            }
        }
        return (w, h, grey)
    }

    public static func screen(from image: MonoImage, options: FromMonoOptions) -> ScreenImage {
        let reduced = reduce(image, options)
        let rep = options.repeats
        let greys = options.scaling > 1 && options.shrink == .grayscale
        var palette: [Color12]
        if options.mode640 {
            let four = greys ? PalettePrototype.grayscale(.mode640).entries : [0x000, 0xFFF, 0x000, 0xFFF]
            palette = four + four + four + four
        } else {
            palette = greys ? PalettePrototype.grayscale(.mode320).entries : ScreenImage.standard320
        }
        var out = ScreenImage(width: reduced.width * rep.x, height: reduced.height * rep.y,
                              is640: options.mode640, palettes: [palette])
        for y in 0..<out.height {
            for x in 0..<out.width {
                let g = reduced.grey[(y / rep.y) * reduced.width + x / rep.x]
                let value: Int
                if options.mode640 {
                    // Grey palette: black, 777, CCC, white. Otherwise entries 0 and 1 are black and white.
                    value = greys ? (g < 60 ? 0 : g < 162 ? 1 : g < 230 ? 2 : 3) : (g >= 128 ? 1 : 0)
                } else {
                    value = greys ? (g + 8) / 17 : (g >= 128 ? 15 : 0)
                }
                out.pixels[y * out.width + x] = UInt8(value)
            }
        }
        return out
    }

    public static func trueColor(from image: MonoImage, options: FromMonoOptions) -> TrueColorImage {
        let reduced = reduce(image, options)
        let rep = options.repeats
        var out = TrueColorImage(width: reduced.width * rep.x, height: reduced.height * rep.y,
                                 tallPixels: options.mode640)
        for y in 0..<out.height {
            for x in 0..<out.width {
                let g = UInt8(reduced.grey[(y / rep.y) * reduced.width + x / rep.x])
                out.setPixel(x, y, g, g, g)
            }
        }
        return out
    }
}
