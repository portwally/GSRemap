import Foundation

/// The less common Apple IIgs load formats. Layouts follow the original's loaders.
public enum IIgsFormats {
    // MARK: DreamGrafix ($C0/$8005), original loaders at 05/6EF6 and 05/6DB9

    public static func loadDreamGrafix(_ d: [UInt8]) throws -> ScreenImage {
        let raw = LZW.decode(d, limit: 32768)
        guard raw.count >= 32200 else { throw FormatError.notThisFormat("a DreamGrafix SHR screen") }
        return try SHRFormats.loadScreen(raw + [UInt8](repeating: 0, count: 32768 - raw.count))
    }

    public static func loadDreamGrafix3200(_ d: [UInt8]) throws -> TrueColorImage {
        let raw = LZW.decode(d, limit: 38400)
        guard raw.count >= 38400 else { throw FormatError.notThisFormat("a DreamGrafix \"3200 color\" screen") }
        return try SHRFormats.load3200(raw).toTrueColor()
    }

    // MARK: "3200 color" compressed ($C0/$3200), original loader at 05/5DD0

    /// Seven header bytes (the last two give the packed size of the colour tables),
    /// then the packed colour tables, then the packed pixels.
    public static func load3200Compressed(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 7 else { throw FormatError.notThisFormat("a compressed \"3200 color\" picture") }
        // ".3201" files: "APP" marker, the colour tables as they are, then PackBytes pixels.
        // The original doesn't read these; they are common enough to accept here.
        if d.count > 6404, d[0] & 0x7F == 0x41, d[1] & 0x7F == 0x50, d[2] & 0x7F == 0x50, d[3] == 0 {
            let pixels = PackBytes.unpack(d, from: 6404, limit: 32000)
            guard pixels.count == 32000 else { throw FormatError.notThisFormat("a compressed \"3200 color\" picture") }
            return try SHRFormats.load3200(pixels + Array(d[4..<6404])).toTrueColor()
        }
        let tableBytes = word(d, 5)
        guard 7 + tableBytes <= d.count else { throw FormatError.notThisFormat("a compressed \"3200 color\" picture") }
        let tables = try unpackRuns(Array(d[7..<(7 + tableBytes)]), count: 6400)
        let pixels = try unpackRuns(Array(d[(7 + tableBytes)...]), count: 32000)
        return try SHRFormats.load3200(pixels + tables).toTrueColor()
    }

    /// Top three bits of each control byte pick the operation, the low five the count
    /// (ops 1 and 7 carry a 13-bit count in two bytes).
    static func unpackRuns(_ d: [UInt8], count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var i = 0
        func next() throws -> UInt8 {
            guard i < d.count else { throw FormatError.notThisFormat("a compressed \"3200 color\" picture") }
            i += 1
            return d[i - 1]
        }
        while out.count < count {
            let control = try next()
            let op = Int(control >> 5)
            var n = Int(control & 0x1F)
            if op == 1 || op == 7 { n = n << 8 | Int(try next()) }
            switch op {
            case 0, 1:
                out.append(contentsOf: repeatElement(try next(), count: n + 1))
            case 6, 7:
                for _ in 0..<n { out.append(try next()) }
            default:
                var unit: [UInt8] = []
                for _ in 0..<op { unit.append(try next()) }
                for _ in 0...n { out.append(contentsOf: unit) }
            }
        }
        return Array(out.prefix(count))
    }

    // MARK: Paintworks Gold 640 mode files, original loader at 05/6C04

    /// Paintworks Gold writes 640 mode pictures with 320 mode headers; this reads them
    /// the way the picture was meant, ignoring what the header says.
    public static func loadPaintworksGold(_ d: [UInt8]) throws -> ScreenImage {
        if SHRFormats.isApplePreferred(d) {
            return try SHRFormats.loadApplePreferred(d, force640: true)
        }
        if d.count >= 32000 && d.count <= 33280 {
            let screen = try SHRFormats.loadScreen(d)
            var fixed = ScreenImage(width: 640, height: 200, is640: true, palettes: screen.palettes)
            for y in 0..<200 { fixed.setPackedRow(y, Array(d[(y * 160)..<(y * 160 + 160)])) }
            return fixed
        }
        // Paint format: the palette in the file is unusable, so the standard one is used.
        guard d.count > 0x222 else { throw FormatError.notThisFormat("a Paintworks Gold picture") }
        let raw = PackBytes.unpack(d, from: 0x222)
        let height = raw.count / 160
        guard height > 0 else { throw FormatError.notThisFormat("a Paintworks Gold picture") }
        var screen = ScreenImage(width: 640, height: height, is640: true)
        for y in 0..<height { screen.setPackedRow(y, Array(raw[(y * 160)..<(y * 160 + 160)])) }
        return screen
    }

    // MARK: Print Shop, original loaders at 05/8767, 05/87B4 and 05/8AC8

    static let printShopColours: [UInt8] = [15, 4, 7, 3, 9, 10, 6, 0]

    /// 88 x 52. One plane (black & white) or three planes: yellow, magenta, cyan.
    static func printShopGraphic(_ d: [UInt8], at start: Int, colour: Bool) -> ScreenImage {
        var screen = ScreenImage(width: 88, height: 52, is640: false)
        for y in 0..<52 {
            for x in 0..<88 {
                let at = start + y * 11 + x / 8
                let mask = UInt8(0x80) >> UInt8(x & 7)
                func plane(_ n: Int) -> Int {
                    let i = at + (colour ? n * 572 : 0)
                    return i < d.count && d[i] & mask != 0 ? 1 : 0
                }
                screen.pixels[y * 88 + x] = printShopColours[plane(0) << 2 | plane(1) << 1 | plane(2)]
            }
        }
        return screen
    }

    public static func loadPrintShop(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 572 else { throw FormatError.notThisFormat("a Print Shop graphic") }
        return printShopGraphic(d, at: 0, colour: false)
    }

    public static func loadPrintShopGS(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 1716 else { throw FormatError.notThisFormat("a Print Shop IIgs color graphic") }
        return printShopGraphic(d, at: 0, colour: true)
    }

    /// GRAPHIC.CGT0-7 from the Print Shop IIgs disk: several colour graphics, names at the end.
    public static func loadPrintShopLibrary(_ d: [UInt8]) throws -> LoadedImage {
        let count = d.count / 1716
        guard count > 0 else { throw FormatError.notThisFormat("a Print Shop IIgs graphics library") }
        var names: [String] = []
        var i = count * 1716
        while i < d.count && names.count < count {
            var j = i
            while j < d.count && d[j] != 0 { j += 1 }
            let text = String(decoding: d[i..<j].map { $0 & 0x7F }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { names.append(text) }
            i = j + 1
        }
        let titles = (0..<count).map { $0 < names.count ? names[$0] : "Graphic \($0 + 1)" }
        return .choice(titles: titles) { .screen(printShopGraphic(d, at: $0 * 1716, colour: true)) }
    }

    // MARK: Finder icon file ($CA), original loader at 05/7394

    struct Icon {
        let name: String
        let large: Bool
        let offset: Int
    }

    public static func loadIconFile(_ d: [UInt8]) throws -> LoadedImage {
        guard d.count > 28, word(d, 4) == 1 else { throw FormatError.notThisFormat("a Finder icon file") }
        var icons: [Icon] = []
        var at = 26
        while at + 2 <= d.count {
            let length = word(d, at)
            guard length > 0, at + length <= d.count, length > 94 else { break }
            let nameLength = min(15, Int(d[at + 66]))
            var name = String(decoding: d[(at + 67)..<(at + 67 + nameLength)], as: UTF8.self)
            if name.isEmpty { name = String(format: "type $%02X", word(d, at + 82) & 0xFF) }
            let large = at + 86
            let small = large + 8 + 2 * word(d, large + 2)
            icons.append(Icon(name: name, large: true, offset: large))
            if small + 8 <= at + length { icons.append(Icon(name: name, large: false, offset: small)) }
            at += length
        }
        guard !icons.isEmpty else { throw FormatError.notThisFormat("a Finder icon file") }
        let titles = icons.map { "\($0.name) (\($0.large ? "large" : "small"))" }
        return .choice(titles: titles) { .screen(try renderIcon(d, at: icons[$0].offset)) }
    }

    /// 640 mode, default palette, a few pixels of white around the icon.
    static func renderIcon(_ d: [UInt8], at p: Int) throws -> ScreenImage {
        let size = word(d, p + 2), height = word(d, p + 4), width = word(d, p + 6)
        guard height > 0, width > 0, size >= height, p + 8 + 2 * size <= d.count else {
            throw FormatError.notThisFormat("a Finder icon")
        }
        let rowBytes = size / height
        let marginX = 8, marginY = 4
        var screen = ScreenImage(width: width * 2 + marginX * 2, height: height + marginY * 2, is640: true)
        for i in 0..<screen.pixels.count { screen.pixels[i] = 3 }
        for y in 0..<height {
            for x in 0..<width where x / 2 < rowBytes {
                let shift = UInt8(x & 1 == 0 ? 4 : 0)
                let image = (d[p + 8 + y * rowBytes + x / 2] >> shift) & 15
                let mask = (d[p + 8 + size + y * rowBytes + x / 2] >> shift) & 15
                if mask == 0 { continue }
                let o = (y + marginY) * screen.width + marginX + x * 2
                screen.pixels[o] = image >> 2
                screen.pixels[o + 1] = image & 3
            }
        }
        return screen
    }

    // MARK: Video digitizers

    /// AST VisionPlus picture data (05/5974): red, green and blue planes,
    /// each 200 rows of 160 bytes holding two 4-bit samples.
    public static func loadAST(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count >= 96000 else { throw FormatError.notThisFormat("an AST picture data file") }
        var image = TrueColorImage(width: 320, height: 200)
        for y in 0..<200 {
            for x in 0..<320 {
                func sample(_ plane: Int) -> UInt8 {
                    let b = d[plane * 32000 + y * 160 + x / 2]
                    return (x & 1 == 0 ? b >> 4 : b & 15) * 17
                }
                image.setPixel(x, y, sample(0), sample(1), sample(2))
            }
        }
        return image
    }

    /// ComputerEyes GS raw data (05/6206): red, green and blue planes of 6-bit samples
    /// stored column by column.
    public static func loadComputerEyes(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count >= 192000 else { throw FormatError.notThisFormat("a ComputerEyes GS raw data file") }
        let stride = d.count >= 196605 ? 65535 : 64000
        var image = TrueColorImage(width: 320, height: 200)
        for y in 0..<200 {
            for x in 0..<320 {
                func sample(_ plane: Int) -> UInt8 {
                    let v = d[plane * stride + x * 200 + y] & 0x3F
                    return v << 2 | v >> 4
                }
                image.setPixel(x, y, sample(0), sample(1), sample(2))
            }
        }
        return image
    }
}

extension AppleIIFormats {
    /// ThunderScan raw scan (05/6154): 256-byte header, then rows of 4-bit grey samples.
    public static func loadThunderScan(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 256 else { throw FormatError.notThisFormat("a ThunderScan raw scan file") }
        let width = word(d, 0x0F), height = word(d, 0x1E) + 1
        let rowBytes = width / 2
        guard width > 1, 256 + rowBytes * height <= d.count else {
            throw FormatError.notThisFormat("a ThunderScan raw scan file")
        }
        var image = TrueColorImage(width: rowBytes * 2, height: height, tallPixels: d[0x0A] & 1 != 0)
        for y in 0..<height {
            for x in 0..<(rowBytes * 2) {
                let b = d[256 + y * rowBytes + x / 2]
                let grey = (x & 1 == 0 ? b >> 4 : b & 15) * 17
                image.setPixel(x, y, grey, grey, grey)
            }
        }
        return image
    }

    public static func loadHiResMono(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 8184 else { throw FormatError.notThisFormat("an Apple II HiRes screen") }
        var screen = ScreenImage(width: 280, height: 192, is640: false)
        for y in 0..<192 {
            let base = rowOffset(y)
            for x in 0..<280 where base + x / 7 < d.count {
                if d[base + x / 7] & (1 << UInt8(x % 7)) != 0 { screen.pixels[y * 280 + x] = 15 }
            }
        }
        return screen
    }

    // MARK: TDM text screen captures (05/771B, 05/7734)

    /// 7 x 8 glyphs for characters $20…$7E, one byte per row, bit 6 = leftmost pixel.
    /// The original read the IIgs character ROM; the app supplies these from a font.
    public static var textGlyphs: [[UInt8]]?

    /// A raw copy of text screen memory: 40 columns, or 80 with the auxiliary half first.
    public static func loadTextScreen(_ d: [UInt8], columns: Int) throws -> ScreenImage {
        guard let glyphs = textGlyphs else {
            throw FormatError.unsupported("The Apple II character set isn't available.")
        }
        let wide = columns == 80
        guard d.count >= (wide ? 1912 : 888) else { throw FormatError.notThisFormat("a text screen capture") }
        var screen = ScreenImage(width: columns * 7, height: 192, is640: wide)
        let white = UInt8(wide ? 3 : 15)
        for row in 0..<24 {
            let base = (row & 7) * 0x80 + (row >> 3) * 0x28
            for column in 0..<columns {
                let at = wide ? base + column / 2 + (column & 1 == 0 ? 0 : 1024) : base + column
                guard at < d.count else { continue }
                let code = Int(d[at])
                var ch = code & 0x7F
                if ch < 0x20 { ch += 0x40 }
                let inverse = code < 0x80
                let glyph = ch >= 0x20 && ch <= 0x7E ? glyphs[ch - 0x20] : [UInt8](repeating: 0, count: 8)
                for gy in 0..<8 {
                    for gx in 0..<7 {
                        let on = glyph[gy] & (0x40 >> UInt8(gx)) != 0
                        if on != inverse { screen.pixels[(row * 8 + gy) * screen.width + column * 7 + gx] = white }
                    }
                }
            }
        }
        return screen
    }
}
