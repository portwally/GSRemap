import Foundation

public struct RemapOptions {
    public var mode: GraphicMode
    public var prototype: PalettePrototype
    public var algorithm: RenderAlgorithm
    public var outputWidth: Int
    public var outputHeight: Int
    public var multipalette: MultipaletteOption

    public init(mode: GraphicMode = .mode320, prototype: PalettePrototype? = nil,
                algorithm: RenderAlgorithm = .patternDither, outputWidth: Int, outputHeight: Int,
                multipalette: MultipaletteOption = .standard) {
        self.mode = mode
        self.prototype = prototype ?? PalettePrototype.calculated(mode)
        self.algorithm = algorithm
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.multipalette = multipalette
    }
}

/// True colour → screen image conversion ("Remap" in the original, 08/9F28 onward).
public enum Remapper {
    /// A true-colour image scaled to the output size, as separate 8-bit planes.
    struct Planes {
        var width: Int
        var height: Int
        var r: [UInt8]
        var g: [UInt8]
        var b: [UInt8]

        @inline(__always) func colour(_ i: Int) -> Int {
            ((Int(r[i]) >> 4) << 8) | ((Int(g[i]) >> 4) << 4) | (Int(b[i]) >> 4)
        }
    }

    /// Size a 1:1 remap gives, allowing for the pixel shape of each mode.
    public static func naturalSize(of image: TrueColorImage, mode: GraphicMode) -> (width: Int, height: Int) {
        if mode.is640 && !image.tallPixels { return (image.width * 2, image.height) }
        if !mode.is640 && image.tallPixels { return (max(1, image.width / 2), image.height) }
        return (image.width, image.height)
    }

    /// Box-average when reducing, replication when enlarging (08/B1C0 GetScaLine).
    static func scale(_ image: TrueColorImage, width outW: Int, height outH: Int) -> Planes {
        func spans(_ src: Int, _ out: Int) -> [(Int, Int)] {
            (0..<out).map { i in
                let a = i * src / out
                let b = max(a + 1, (i + 1) * src / out)
                return (a, min(b, src))
            }
        }
        let xs = spans(image.width, outW), ys = spans(image.height, outH)
        var planes = Planes(width: outW, height: outH,
                            r: [UInt8](repeating: 0, count: outW * outH),
                            g: [UInt8](repeating: 0, count: outW * outH),
                            b: [UInt8](repeating: 0, count: outW * outH))
        image.rgb.withUnsafeBufferPointer { src in
            for y in 0..<outH {
                let (y0, y1) = ys[y]
                for x in 0..<outW {
                    let (x0, x1) = xs[x]
                    var sr = 0, sg = 0, sb = 0
                    for sy in y0..<y1 {
                        var i = (sy * image.width + x0) * 3
                        for _ in x0..<x1 {
                            sr += Int(src[i])
                            sg += Int(src[i + 1])
                            sb += Int(src[i + 2])
                            i += 3
                        }
                    }
                    let n = (y1 - y0) * (x1 - x0)
                    let o = y * outW + x
                    planes.r[o] = UInt8(sr / n)
                    planes.g[o] = UInt8(sg / n)
                    planes.b[o] = UInt8(sb / n)
                }
            }
        }
        return planes
    }

    static func histogram(_ planes: Planes, lines: Range<Int>) -> [UInt16] {
        var hist = [UInt16](repeating: 0, count: 4096)
        for i in (lines.lowerBound * planes.width)..<(lines.upperBound * planes.width) {
            let c = planes.colour(i)
            if hist[c] != 0xFFFF { hist[c] += 1 }
        }
        return hist
    }

    /// Expands a 4-, 8- or 16-entry prototype result into a 16-entry colour table.
    static func colourTable(_ entries: [UInt16]) -> [Color12] {
        let clean = entries.map { $0 & 0x0FFF }
        switch clean.count {
        case 4: return clean + clean + clean + clean
        case 8: return clean + clean
        default: return clean
        }
    }

    public static func remap(_ image: TrueColorImage, options: RemapOptions) -> ScreenImage {
        let planes = scale(image, width: max(1, options.outputWidth), height: max(1, options.outputHeight))
        if options.mode == .multipalette { return remapMultipalette(planes, options: options) }

        let entries = PaletteCalculator.calculate(prototype: options.prototype.entries,
                                                  histogram: histogram(planes, lines: 0..<planes.height))
        var screen = ScreenImage(width: planes.width, height: planes.height, is640: options.mode.is640,
                                 palettes: [colourTable(entries)])
        render(planes, lines: 0..<planes.height, entries: entries, algorithm: options.algorithm, into: &screen)
        return screen
    }

    /// Renders some lines with one palette (08/BDCE, BED3, BFBD).
    static func render(_ planes: Planes, lines: Range<Int>, entries: [UInt16],
                       algorithm: RenderAlgorithm, into screen: inout ScreenImage) {
        let grey = entries.allSatisfy { $0 & 0x8000 != 0 || ColorMath.isGrey($0 & 0x0FFF) }
        let w = planes.width

        if grey {
            let diffuse = algorithm == .errorDiffusion
            let table = PatternTable(palette: entries, pattern: algorithm == .patternDither)
            let cache = (0..<256).map { table.lookup(r: $0, g: $0, b: $0) }
            if !diffuse {
                for y in lines {
                    for x in 0..<w {
                        let i = y * w + x
                        let level = ColorMath.grey(Int(planes.r[i]), Int(planes.g[i]), Int(planes.b[i]))
                        let bytes = cache[level]
                        screen.pixels[i] = table.pixel(byte: y & 1 == 0 ? bytes.even : bytes.odd, column: x)
                    }
                }
                return
            }
            // Floyd-Steinberg, serpentine scan.
            var current = [Int](repeating: 0, count: w + 2)
            var next = [Int](repeating: 0, count: w + 2)
            for y in lines {
                let leftToRight = (y - lines.lowerBound) & 1 == 0
                var x = leftToRight ? 0 : w - 1
                let step = leftToRight ? 1 : -1
                for _ in 0..<w {
                    let i = y * w + x
                    let level = ColorMath.grey(Int(planes.r[i]), Int(planes.g[i]), Int(planes.b[i]))
                    let wanted = level + ((current[x + 1] + 8) >> 4)
                    let byte = cache[min(255, max(0, wanted))].even
                    screen.pixels[i] = table.pixel(byte: byte, column: x)
                    let error = wanted - table.greyIntensity(byte: byte, column: x)
                    current[x + 1 + step] += error * 7
                    next[x + 1 - step] += error * 3
                    next[x + 1] += error * 5
                    next[x + 1 + step] += error
                    x += step
                }
                swap(&current, &next)
                for k in 0..<next.count { next[k] = 0 }
            }
            return
        }

        // Colour: error diffusion is not offered, so it falls back to pattern dither.
        let table = PatternTable(palette: entries, pattern: algorithm != .closestMatch)
        var cache = [UInt16](repeating: 0, count: 4096)
        var cached = [Bool](repeating: false, count: 4096)
        for y in lines {
            for x in 0..<w {
                let i = y * w + x
                let c = planes.colour(i)
                if !cached[c] {
                    let bytes = table.lookup(colour: UInt16(c))
                    cache[c] = UInt16(bytes.even) << 8 | UInt16(bytes.odd)
                    cached[c] = true
                }
                let byte = UInt8(truncatingIfNeeded: y & 1 == 0 ? cache[c] >> 8 : cache[c])
                screen.pixels[i] = table.pixel(byte: byte, column: x)
            }
        }
    }

    // MARK: Multipalette

    /// 320 mode with a palette per line, up to 16 palettes.
    /// The original's selection code is not ported one for one: zones are seeded evenly,
    /// then lines migrate to whichever palette suits them best.
    static func remapMultipalette(_ planes: Planes, options: RemapOptions) -> ScreenImage {
        let h = planes.height
        let count = min(options.multipalette.maxPalettes, h)
        var prototype = options.prototype.entries
        if prototype.count != 16 { prototype = PalettePrototype.calculated(.mode320).entries }

        var lineHists: [[Int: Int]] = []
        for y in 0..<h {
            var d: [Int: Int] = [:]
            for x in 0..<planes.width { d[planes.colour(y * planes.width + x), default: 0] += 1 }
            lineHists.append(d)
        }
        var owner = (0..<h).map { $0 * count / h }

        func palettes(for owner: [Int], previous: [[UInt16]]?) -> [[UInt16]] {
            (0..<count).map { p in
                var hist = [UInt16](repeating: 0, count: 4096)
                var any = false
                for y in 0..<h where owner[y] == p {
                    any = true
                    for (c, n) in lineHists[y] { hist[c] = UInt16(min(0xFFFF, Int(hist[c]) + n)) }
                }
                if !any, let previous { return previous[p] }
                return PaletteCalculator.calculate(prototype: prototype, histogram: hist)
            }
        }

        var tables = palettes(for: owner, previous: nil)
        let passes: Int
        switch options.multipalette {
        case .zones, .zonesMax8: passes = 0
        case .optimized: passes = 8
        default: passes = 2
        }
        for _ in 0..<passes {
            var changed = false
            for y in 0..<h {
                var best = owner[y], bestCost = Int.max
                for p in 0..<count {
                    var cost = 0
                    for (c, n) in lineHists[y] {
                        var nearest = Int.max
                        for e in tables[p] where e & 0x8000 == 0 {
                            nearest = min(nearest, ColorMath.distance(UInt16(c), e & 0x0FFF))
                        }
                        cost += nearest * n
                        if cost >= bestCost { break }
                    }
                    if cost < bestCost {
                        bestCost = cost
                        best = p
                    }
                }
                if best != owner[y] {
                    owner[y] = best
                    changed = true
                }
            }
            if !changed { break }
            tables = palettes(for: owner, previous: tables)
        }

        var screen = ScreenImage(width: planes.width, height: h, is640: false,
                                 palettes: tables.map { colourTable($0) })
        // Error diffusion needs a grey palette on every line; otherwise use pattern dither.
        let algorithm = options.algorithm
        var y = 0
        while y < h {
            var end = y + 1
            while end < h && owner[end] == owner[y] { end += 1 }
            render(planes, lines: y..<end, entries: tables[owner[y]], algorithm: algorithm, into: &screen)
            for line in y..<end { screen.scbs[line] = UInt8(owner[y]) }
            y = end
        }
        return screen
    }

    // MARK: Quick remap

    /// Fast preview: one 320-mode screen, fixed palette, ordered dither (08/B762).
    public static func quickRemap(_ image: TrueColorImage) -> ScreenImage {
        let natural = naturalSize(of: image, mode: .mode320)
        let planes = scale(image, width: natural.width, height: natural.height)
        let w = min(320, planes.width), h = min(200, planes.height)
        var screen = ScreenImage(width: w, height: h, is640: false,
                                 palettes: [PalettePrototype.quickRemap.map { $0 & 0x0FFF }])
        let thresholds = [5, 12, 14, 9]
        for y in 0..<h {
            for x in 0..<w {
                let i = y * planes.width + x
                let r = Int(planes.r[i]) >> 4, g = Int(planes.g[i]) >> 4, b = Int(planes.b[i]) >> 4
                let t = thresholds[(y & 1) * 2 + (x & 1)]
                let index = (r >= t ? 4 : 0) | (g >= t ? 2 : 0) | (b >= t ? 1 : 0)
                screen.pixels[y * w + x] = UInt8(index == 7 ? 15 : index)
            }
        }
        return screen
    }
}
