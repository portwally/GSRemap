import Foundation

@inline(__always) func wordBE(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) << 8 | Int(d[i + 1]) }
@inline(__always) func longBE(_ d: [UInt8], _ i: Int) -> Int { wordBE(d, i) << 16 | wordBE(d, i + 2) }

/// PackBits, also known as ByteRun1 on the Amiga.
func unpackBits(_ d: [UInt8], from start: Int, count: Int) -> (bytes: [UInt8], next: Int) {
    var out: [UInt8] = []
    out.reserveCapacity(count)
    var i = start
    while out.count < count && i < d.count {
        let n = Int(Int8(bitPattern: d[i]))
        i += 1
        if n >= 0 {
            let end = min(i + n + 1, d.count)
            out.append(contentsOf: d[i..<end])
            i = end
        } else if n != -128 {
            guard i < d.count else { break }
            out.append(contentsOf: repeatElement(d[i], count: 1 - n))
            i += 1
        }
    }
    if out.count < count { out.append(contentsOf: repeatElement(0, count: count - out.count)) }
    return (Array(out.prefix(count)), i)
}

private let blackAndWhite640: [Color12] = [0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF,
                                           0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF]

// MARK: - Atari ST

public enum AtariFormats {
    /// ST palette word → IIgs colour. Plain ST words carry 3 bits per channel;
    /// STE words carry a fourth, least significant bit in bit 3 of each nibble.
    static func colours(_ words: [Int]) -> [Color12] {
        let enhanced = words.contains { $0 & 0x888 != 0 }
        func channel(_ n: Int) -> Int {
            enhanced ? ((n & 7) << 1 | (n >> 3) & 1) : ((n & 7) << 1 | (n & 7) >> 2)
        }
        return words.map { Color12(channel($0 >> 8) << 8 | channel($0 >> 4) << 4 | channel($0)) }
    }

    /// Builds a picture from 32000 bytes of ST screen memory (interleaved bit planes).
    /// Low resolution gives a 320 mode screen, medium a 640 mode screen, and high
    /// (640 x 400 black & white) a 640 mode screen 400 lines tall.
    static func screen(resolution: Int, palette: [Int], memory: [UInt8]) throws -> ScreenImage {
        guard memory.count >= 32000, (0...2).contains(resolution) else {
            throw FormatError.notThisFormat("an Atari ST picture")
        }
        let table = colours(palette)
        switch resolution {
        case 0:
            var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [table])
            for y in 0..<200 {
                for x in 0..<320 {
                    let at = y * 160 + (x >> 4) * 8
                    let bit = 15 - (x & 15)
                    var v = 0
                    for plane in 0..<4 { v |= ((wordBE(memory, at + plane * 2) >> bit) & 1) << plane }
                    s.pixels[y * 320 + x] = UInt8(v)
                }
            }
            return s
        case 1:
            let four = Array(table.prefix(4))
            var s = ScreenImage(width: 640, height: 200, is640: true, palettes: [four + four + four + four])
            for y in 0..<200 {
                for x in 0..<640 {
                    let at = y * 160 + (x >> 4) * 4
                    let bit = 15 - (x & 15)
                    let v = (wordBE(memory, at) >> bit) & 1 | ((wordBE(memory, at + 2) >> bit) & 1) << 1
                    s.pixels[y * 640 + x] = UInt8(v)
                }
            }
            return s
        default:
            var s = ScreenImage(width: 640, height: 400, is640: true, palettes: [blackAndWhite640])
            // Colour 0 is normally white, so a set bit is ink.
            let inkIsBlack = palette.first.map { $0 & 1 != 0 } ?? true
            for y in 0..<400 {
                for x in 0..<640 {
                    let set = memory[y * 80 + (x >> 3)] & (0x80 >> UInt8(x & 7)) != 0
                    s.pixels[y * 640 + x] = set == inkIsBlack ? 0 : 1
                }
            }
            return s
        }
    }

    /// Degas .PI1, .PI2, .PI3
    public static func loadDegas(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 32034 else { throw FormatError.notThisFormat("a Degas picture") }
        return try screen(resolution: wordBE(d, 0) & 3, palette: (0..<16).map { wordBE(d, 2 + $0 * 2) },
                          memory: Array(d[34..<32034]))
    }

    /// Degas Elite .PC1, .PC2, .PC3: each scan line packed plane by plane.
    public static func loadDegasElite(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count > 34 else { throw FormatError.notThisFormat("a Degas Elite picture") }
        let resolution = wordBE(d, 0) & 3
        guard resolution <= 2 else { throw FormatError.notThisFormat("a Degas Elite picture") }
        let planes = [4, 2, 1][resolution], lines = resolution == 2 ? 400 : 200
        let lineBytes = 32000 / lines, planeBytes = lineBytes / planes
        let raw = unpackBits(d, from: 34, count: 32000).bytes
        var memory = [UInt8](repeating: 0, count: 32000)
        for y in 0..<lines {
            for plane in 0..<planes {
                for i in 0..<planeBytes {
                    memory[y * lineBytes + (i / 2) * planes * 2 + plane * 2 + (i & 1)] =
                        raw[y * lineBytes + plane * planeBytes + i]
                }
            }
        }
        return try screen(resolution: resolution, palette: (0..<16).map { wordBE(d, 2 + $0 * 2) }, memory: memory)
    }

    /// Neochrome .NEO
    public static func loadNeochrome(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 32128 else { throw FormatError.notThisFormat("a Neochrome picture") }
        return try screen(resolution: wordBE(d, 2) & 3, palette: (0..<16).map { wordBE(d, 4 + $0 * 2) },
                          memory: Array(d[128..<32128]))
    }

    /// Tiny .TNY: run-length packed words, stored column by column within each plane.
    public static func loadTiny(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count > 37 else { throw FormatError.notThisFormat("a Tiny picture") }
        var p = 0
        var resolution = Int(d[0])
        p = 1
        if resolution > 2 {
            resolution -= 3
            p += 4
        }
        guard resolution <= 2, p + 36 <= d.count else { throw FormatError.notThisFormat("a Tiny picture") }
        let palette = (0..<16).map { wordBE(d, p + $0 * 2) }
        p += 32
        let controlCount = wordBE(d, p)
        var control = p + 4
        var data = control + controlCount
        let controlEnd = data
        var words: [Int] = []
        words.reserveCapacity(16000)
        func nextWord() -> Int {
            guard data + 1 < d.count else { return 0 }
            data += 2
            return wordBE(d, data - 2)
        }
        while control < controlEnd && words.count < 16000 {
            let c = Int(Int8(bitPattern: d[control]))
            control += 1
            if c < 0 {
                for _ in 0..<(-c) { words.append(nextWord()) }
            } else if c == 0 || c == 1 {
                guard control + 1 < d.count else { break }
                let n = wordBE(d, control)
                control += 2
                if c == 0 {
                    words.append(contentsOf: repeatElement(nextWord(), count: n))
                } else {
                    for _ in 0..<n { words.append(nextWord()) }
                }
            } else {
                words.append(contentsOf: repeatElement(nextWord(), count: c))
            }
        }
        words.append(contentsOf: repeatElement(0, count: max(0, 16000 - words.count)))
        var memory = [UInt8](repeating: 0, count: 32000)
        var i = 0
        for plane in 0..<4 {
            for column in 0..<20 {
                for row in 0..<200 {
                    let at = row * 160 + column * 8 + plane * 2
                    memory[at] = UInt8(words[i] >> 8)
                    memory[at + 1] = UInt8(words[i] & 0xFF)
                    i += 1
                }
            }
        }
        return try screen(resolution: resolution, palette: palette, memory: memory)
    }

    /// Spectrum 512: 199 lines, each with three 16-colour palettes that take over at
    /// set positions across the line. `planes` is 4 x 199 x 40 bytes, plane by plane.
    static func spectrum(pixel: (_ x: Int, _ line: Int) -> Int, palettes: [Int]) -> TrueColorImage {
        var image = TrueColorImage(width: 320, height: 200)
        for line in 1..<200 {
            let set = Array(palettes[((line - 1) * 48)..<(line * 48)])
            let table = colours(set)
            for x in 0..<320 {
                var c = pixel(x, line)
                var start = 10 * c
                start += c & 1 == 1 ? -5 : 1
                if x >= start && x < start + 160 { c += 16 } else if x >= start + 160 { c += 32 }
                let (r, g, b) = ColorMath.rgb8(table[c])
                image.setPixel(x, line, r, g, b)
            }
        }
        return image
    }

    /// Spectrum 512 uncompressed .SPU
    public static func loadSpectrum(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count >= 51104 else { throw FormatError.notThisFormat("a Spectrum 512 picture") }
        let palettes = (0..<(199 * 48)).map { wordBE(d, 32000 + $0 * 2) }
        return spectrum(pixel: { x, line in
            let at = line * 160 + (x >> 4) * 8
            let bit = 15 - (x & 15)
            var v = 0
            for plane in 0..<4 { v |= ((wordBE(d, at + plane * 2) >> bit) & 1) << plane }
            return v
        }, palettes: palettes)
    }

    /// Spectrum 512 compressed .SPC
    public static func loadSpectrumCompressed(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 12, d[0] == 0x53, d[1] == 0x50 else {
            throw FormatError.notThisFormat("a compressed Spectrum 512 picture")
        }
        let bitmapBytes = longBE(d, 4)
        guard 12 + bitmapBytes <= d.count else { throw FormatError.notThisFormat("a compressed Spectrum 512 picture") }
        var planes: [UInt8] = []
        planes.reserveCapacity(31840)
        var i = 12
        while planes.count < 31840 && i < 12 + bitmapBytes {
            let n = Int(Int8(bitPattern: d[i]))
            i += 1
            if n >= 0 {
                let end = min(i + n + 1, d.count)
                planes.append(contentsOf: d[i..<end])
                i = end
            } else {
                guard i < d.count else { break }
                planes.append(contentsOf: repeatElement(d[i], count: 2 - n))
                i += 1
            }
        }
        planes.append(contentsOf: repeatElement(0, count: max(0, 31840 - planes.count)))
        var palettes: [Int] = []
        palettes.reserveCapacity(199 * 48)
        var p = 12 + bitmapBytes
        for _ in 0..<(199 * 3) {
            let mask = p + 1 < d.count ? wordBE(d, p) : 0
            p += 2
            for bit in 0..<16 {
                if mask & (1 << bit) != 0, p + 1 < d.count {
                    palettes.append(wordBE(d, p))
                    p += 2
                } else {
                    palettes.append(0)
                }
            }
        }
        return spectrum(pixel: { x, line in
            var v = 0
            for plane in 0..<4 {
                let byte = planes[plane * 7960 + (line - 1) * 40 + (x >> 3)]
                v |= Int((byte >> UInt8(7 - (x & 7))) & 1) << plane
            }
            return v
        }, palettes: palettes)
    }
}

// MARK: - Amiga

public enum AmigaFormats {
    /// IFF FORM ILBM, including Extra HalfBrite, HAM and 24-bit pictures (and PC DeluxePaint PBM).
    public static func loadIFF(_ d: [UInt8]) throws -> TrueColorImage {
        func tag(_ i: Int) -> String { i + 4 <= d.count ? String(decoding: d[i..<(i + 4)], as: UTF8.self) : "" }
        // The picture may be buried inside other structures: look for the first ILBM or PBM form.
        var form = -1
        var chunky = false
        var i = 0
        while i + 12 <= d.count {
            if tag(i) == "FORM", tag(i + 8) == "ILBM" || tag(i + 8) == "PBM " {
                form = i
                chunky = tag(i + 8) == "PBM "
                break
            }
            i += 1
        }
        guard form >= 0 else { throw FormatError.notThisFormat("an IFF picture (FORM ILBM)") }
        let end = min(d.count, form + 8 + longBE(d, form + 4))
        var width = 0, height = 0, planes = 0, masking = 0, compression = 0
        var cmap: [(UInt8, UInt8, UInt8)] = []
        var viewMode: Int?
        var body: (start: Int, length: Int)?
        var p = form + 12
        while p + 8 <= end {
            let length = longBE(d, p + 4)
            let at = p + 8
            switch tag(p) {
            case "BMHD" where at + 11 <= d.count:
                width = wordBE(d, at)
                height = wordBE(d, at + 2)
                planes = Int(d[at + 8])
                masking = Int(d[at + 9])
                compression = Int(d[at + 10])
            case "CMAP":
                cmap = (0..<(length / 3)).compactMap {
                    at + $0 * 3 + 2 < d.count ? (d[at + $0 * 3], d[at + $0 * 3 + 1], d[at + $0 * 3 + 2]) : nil
                }
            case "CAMG" where at + 4 <= d.count:
                viewMode = longBE(d, at)
            case "BODY":
                body = (at, min(length, d.count - at))
            default:
                break
            }
            p = at + length + (length & 1)
        }
        guard let body, width > 0, height > 0, planes > 0, planes <= 32 else {
            throw FormatError.notThisFormat("an IFF picture (FORM ILBM)")
        }
        // Old pictures stored colours with only the high nibble set.
        if !cmap.isEmpty, cmap.allSatisfy({ $0.0 & 15 == 0 && $0.1 & 15 == 0 && $0.2 & 15 == 0 }) {
            cmap = cmap.map { ($0.0 | $0.0 >> 4, $0.1 | $0.1 >> 4, $0.2 | $0.2 >> 4) }
        }
        let ham = planes != 24 && ((viewMode ?? 0) & 0x800 != 0 || (viewMode == nil && planes == 6 && cmap.count == 16))
        let halfBrite = !ham && planes == 6 && ((viewMode ?? 0x80) & 0x80 != 0)
        let hires = (viewMode ?? 0) & 0x8000 != 0, lace = (viewMode ?? 0) & 4 != 0

        var image = TrueColorImage(width: width, height: height, tallPixels: hires && !lace)
        let rowBytes = chunky ? (width + 1) & ~1 : ((width + 15) / 16) * 2
        let rowPlanes = chunky ? 1 : planes + (masking == 1 ? 1 : 0)
        var cursor = body.start
        for y in 0..<height {
            var row: [UInt8]
            if compression == 1 {
                row = []
                for _ in 0..<rowPlanes {
                    let unpacked = unpackBits(d, from: cursor, count: rowBytes)
                    row += unpacked.bytes
                    cursor = unpacked.next
                }
            } else {
                let stop = min(d.count, cursor + rowBytes * rowPlanes)
                row = Array(d[min(cursor, stop)..<stop])
                row += [UInt8](repeating: 0, count: rowBytes * rowPlanes - row.count)
                cursor += rowBytes * rowPlanes
            }
            var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0
            for x in 0..<width {
                var v = 0
                if chunky {
                    v = Int(row[x])
                } else {
                    for plane in 0..<planes where row[plane * rowBytes + (x >> 3)] & (0x80 >> UInt8(x & 7)) != 0 {
                        v |= 1 << plane
                    }
                }
                if planes == 24 {
                    r = UInt8(v & 0xFF)
                    g = UInt8(v >> 8 & 0xFF)
                    b = UInt8(v >> 16 & 0xFF)
                } else if ham {
                    let dataBits = planes - 2
                    let control = v >> dataBits, value = v & ((1 << dataBits) - 1)
                    let level = dataBits == 4 ? UInt8(value * 17) : UInt8(value << 2 | value >> 4)
                    switch control {
                    case 0: if value < cmap.count { (r, g, b) = cmap[value] }
                    case 1: b = level
                    case 2: r = level
                    default: g = level
                    }
                } else if halfBrite && v >= 32 {
                    if v - 32 < cmap.count {
                        let c = cmap[v - 32]
                        (r, g, b) = (c.0 >> 1, c.1 >> 1, c.2 >> 1)
                    }
                } else if v < cmap.count {
                    (r, g, b) = cmap[v]
                } else {
                    let grey = UInt8(planes >= 8 ? v & 0xFF : v * 255 / max(1, (1 << planes) - 1))
                    (r, g, b) = (grey, grey, grey)
                }
                image.setPixel(x, y, r, g, b)
            }
        }
        return image
    }
}

// MARK: - Commodore 64

public enum C64Formats {
    /// The palette the original uses for C64 pictures (05/4D56); pixel values are C64 colour numbers.
    public static let palette: [Color12] = [
        0x000, 0xFFF, 0xD00, 0x0DD, 0xD0D, 0x0D0, 0x00D, 0xFE0,
        0xF70, 0xB50, 0xF88, 0x666, 0x999, 0xBFB, 0xBBF, 0xCCC,
    ]

    /// Hi-res bitmap: each 8 x 8 cell has an ink (high nibble) and paper (low nibble) colour.
    static func hires(bitmap: ArraySlice<UInt8>, colour: (Int) -> UInt8) -> ScreenImage {
        var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [palette])
        let base = bitmap.startIndex
        for y in 0..<200 {
            for x in 0..<320 {
                let cell = (y >> 3) * 40 + (x >> 3)
                let at = base + cell * 8 + (y & 7)
                let set = at < bitmap.endIndex && bitmap[at] & (0x80 >> UInt8(x & 7)) != 0
                let c = colour(cell)
                s.pixels[y * 320 + x] = set ? c >> 4 : c & 15
            }
        }
        return s
    }

    /// Doodle: load address, 1000 colour bytes, 24 unused, 8000 bitmap bytes.
    public static func loadDoodle(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 9026 else { throw FormatError.notThisFormat("a Doodle picture") }
        return hires(bitmap: d[1026..<min(d.count, 9026)]) { d[2 + $0] }
    }

    /// Print Shop screen: load address, then a bitmap shown white on black.
    public static func loadPrintShop(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 8000 else { throw FormatError.notThisFormat("a C64 Print Shop screen") }
        return hires(bitmap: d[2..<min(d.count, 8002)]) { _ in 0x10 }
    }

    /// Koala: load address, 8000 bitmap, 1000 screen, 1000 colour memory, background.
    /// 160 double-wide pixels per line, four colour choices per 4 x 8 cell.
    public static func loadKoala(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 10003 else { throw FormatError.notThisFormat("a Koala picture") }
        var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [palette])
        let background = d[10002] & 15
        for y in 0..<200 {
            for x in 0..<160 {
                let cell = (y >> 3) * 40 + (x >> 2)
                let pair = (d[2 + cell * 8 + (y & 7)] >> UInt8(6 - 2 * (x & 3))) & 3
                let value: UInt8
                switch pair {
                case 0: value = background
                case 1: value = d[8002 + cell] >> 4
                case 2: value = d[8002 + cell] & 15
                default: value = d[9002 + cell] & 15
                }
                s.pixels[y * 320 + x * 2] = value
                s.pixels[y * 320 + x * 2 + 1] = value
            }
        }
        return s
    }
}

// MARK: - Macintosh

public enum MacFormats {
    /// Skips a MacBinary wrapper if there is one.
    static func dataFork(_ d: [UInt8]) -> Int {
        guard d.count > 128, d[0] == 0, d[1] > 0, d[1] < 64, d[74] == 0, d[82] == 0 else { return 0 }
        let length = longBE(d, 83)
        return length > 0 && length <= d.count - 128 + 127 ? 128 : 0
    }

    /// 576 x 720 one-bit rows; true = ink.
    static func macPaintRows(_ d: [UInt8]) throws -> [[UInt8]] {
        let start = dataFork(d) + 512
        guard d.count > start else { throw FormatError.notThisFormat("a MacPaint picture") }
        var rows: [[UInt8]] = []
        var cursor = start
        for _ in 0..<720 {
            let unpacked = unpackBits(d, from: cursor, count: 72)
            rows.append(unpacked.bytes)
            cursor = unpacked.next
        }
        return rows
    }

    /// 576 x 720 in 320 mode, black & white. (The original had to stop after 227 lines.)
    public static func loadMacPaint320(_ d: [UInt8]) throws -> ScreenImage {
        let rows = try macPaintRows(d)
        var s = ScreenImage(width: 576, height: 720, is640: false)
        for y in 0..<720 {
            for x in 0..<576 where rows[y][x >> 3] & (0x80 >> UInt8(x & 7)) == 0 {
                s.pixels[y * 576 + x] = 15
            }
        }
        return s
    }

    /// 576 x 360 in 640 mode: each pair of lines becomes one line of greys.
    public static func loadMacPaint640(_ d: [UInt8]) throws -> ScreenImage {
        let rows = try macPaintRows(d)
        let greys = PalettePrototype.grayscale(.mode640).entries
        var s = ScreenImage(width: 576, height: 360, is640: true, palettes: [greys + greys + greys + greys])
        for y in 0..<360 {
            for x in 0..<576 {
                let mask = UInt8(0x80) >> UInt8(x & 7)
                let ink = (rows[y * 2][x >> 3] & mask != 0 ? 1 : 0) + (rows[y * 2 + 1][x >> 3] & mask != 0 ? 1 : 0)
                s.pixels[y * 576 + x] = ink == 0 ? 3 : ink == 2 ? 0 : ((x + y) & 1 == 0 ? 1 : 2)
            }
        }
        return s
    }

    /// ScreenMaker startup screen: 512 x 342 one-bit bitmap.
    public static func loadScreenMaker(_ d: [UInt8]) throws -> ScreenImage {
        let start = dataFork(d)
        guard d.count - start >= 21888 else { throw FormatError.notThisFormat("a ScreenMaker startup screen") }
        var s = ScreenImage(width: 512, height: 342, is640: true, palettes: [blackAndWhite640])
        for y in 0..<342 {
            for x in 0..<512 where d[start + y * 64 + (x >> 3)] & (0x80 >> UInt8(x & 7)) == 0 {
                s.pixels[y * 512 + x] = 1
            }
        }
        return s
    }
}
