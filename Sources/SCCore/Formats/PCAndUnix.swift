import Foundation

// MARK: - IBM PC & compatibles

public enum PCFormats {
    static let egaPalette: [(UInt8, UInt8, UInt8)] = [
        (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
        (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85),
        (255, 255, 255),
    ]

    /// PC Paintbrush .PCX and .PCC
    public static func loadPCX(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 128, d[0] == 10 else { throw FormatError.notThisFormat("a PC Paintbrush picture") }
        let bits = Int(d[3]), planes = Int(d[65]), lineBytes = word(d, 66)
        let width = word(d, 8) - word(d, 4) + 1, height = word(d, 10) - word(d, 6) + 1
        guard width > 0, height > 0, lineBytes > 0, planes > 0, [1, 2, 4, 8].contains(bits) else {
            throw FormatError.notThisFormat("a PC Paintbrush picture")
        }
        // Run-length data: a byte with the top two bits set is a repeat count.
        let total = lineBytes * planes * height
        var raw: [UInt8] = []
        raw.reserveCapacity(total)
        var i = 128
        if d[2] == 1 {
            while raw.count < total && i < d.count {
                let b = d[i]
                i += 1
                if b >= 0xC0 {
                    guard i < d.count else { break }
                    raw.append(contentsOf: repeatElement(d[i], count: Int(b & 0x3F)))
                    i += 1
                } else {
                    raw.append(b)
                }
            }
        } else {
            raw = Array(d[128..<min(d.count, 128 + total)])
        }
        raw.append(contentsOf: repeatElement(0, count: max(0, total - raw.count)))

        var palette: [(UInt8, UInt8, UInt8)] = (0..<16).map { (d[16 + $0 * 3], d[17 + $0 * 3], d[18 + $0 * 3]) }
        let colours = 1 << (bits * planes)
        if bits == 8 && planes == 1 {
            if d.count >= 769, d[d.count - 769] == 12 {
                let at = d.count - 768
                palette = (0..<256).map { (d[at + $0 * 3], d[at + $0 * 3 + 1], d[at + $0 * 3 + 2]) }
            } else {
                palette = (0..<256).map { (UInt8($0), UInt8($0), UInt8($0)) }
            }
        } else if colours == 2 {
            // Two-colour files: use the header's colours when it has two, else black and white.
            if palette[0] == palette[1] { palette = [(0, 0, 0), (255, 255, 255)] }
        } else if d[1] == 3 || palette.prefix(colours).allSatisfy({ $0 == palette[0] }) {
            palette = egaPalette
        }

        var image = TrueColorImage(width: width, height: height)
        for y in 0..<height {
            let row = y * lineBytes * planes
            for x in 0..<width {
                if bits == 8 && planes >= 3 {
                    image.setPixel(x, y, raw[row + x], raw[row + lineBytes + x], raw[row + 2 * lineBytes + x])
                    continue
                }
                var v = 0
                for plane in 0..<planes {
                    let byte = Int(raw[row + plane * lineBytes + x * bits / 8])
                    let shift = 8 - bits - (x * bits) % 8
                    v |= ((byte >> shift) & ((1 << bits) - 1)) << (plane * bits)
                }
                let c = v < palette.count ? palette[v] : (0, 0, 0)
                image.setPixel(x, y, c.0, c.1, c.2)
            }
        }
        return image
    }

    /// GEM / Ventura Publisher .IMG: one or more bit planes, shown as greys.
    public static func loadGEM(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 16 else { throw FormatError.notThisFormat("a GEM image") }
        let headerBytes = wordBE(d, 2) * 2, planes = wordBE(d, 4), patternLength = wordBE(d, 6)
        let width = wordBE(d, 12), height = wordBE(d, 14)
        guard wordBE(d, 0) <= 3, headerBytes >= 16, headerBytes < d.count, (1...8).contains(planes),
              width > 0, height > 0, patternLength > 0 else { throw FormatError.notThisFormat("a GEM image") }
        let lineBytes = (width + 7) / 8
        var image = TrueColorImage(width: width, height: height)
        var i = headerBytes
        var y = 0
        while y < height && i < d.count {
            var repeats = 1
            if i + 3 < d.count, d[i] == 0, d[i + 1] == 0, d[i + 2] == 0xFF {
                repeats = max(1, Int(d[i + 3]))
                i += 4
            }
            var rows: [[UInt8]] = []
            for _ in 0..<planes {
                var row: [UInt8] = []
                while row.count < lineBytes && i < d.count {
                    let b = d[i]
                    i += 1
                    if b == 0x80 {
                        guard i < d.count else { break }
                        let n = Int(d[i])
                        i += 1
                        row.append(contentsOf: d[i..<min(d.count, i + n)])
                        i += n
                    } else if b == 0 {
                        guard i < d.count else { break }
                        let n = Int(d[i])
                        i += 1
                        let pattern = Array(d[i..<min(d.count, i + patternLength)])
                        for _ in 0..<n { row.append(contentsOf: pattern) }
                        i += patternLength
                    } else {
                        row.append(contentsOf: repeatElement(b & 0x80 != 0 ? 0xFF : 0x00, count: Int(b & 0x7F)))
                    }
                }
                row.append(contentsOf: repeatElement(0, count: max(0, lineBytes - row.count)))
                rows.append(row)
            }
            let top = (1 << planes) - 1
            for _ in 0..<repeats where y < height {
                for x in 0..<width {
                    var v = 0
                    for plane in 0..<planes where rows[plane][x >> 3] & (0x80 >> UInt8(x & 7)) != 0 { v |= 1 << plane }
                    // A set bit is ink: 0 is white, all bits set is black.
                    let grey = UInt8(255 - v * 255 / top)
                    image.setPixel(x, y, grey, grey, grey)
                }
                y += 1
            }
        }
        return image
    }

    /// One frame written by the FliAway utility (original loader at 05/6060): 256 colour
    /// words, a packed-size word (0 = not packed), then 320 x 200 bytes, PackBytes-packed.
    public static func loadFliAwayFrame(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 514 else { throw FormatError.notThisFormat("an Animator frame file") }
        let packed = word(d, 512)
        let pixels: [UInt8] = packed == 0
            ? Array(d[514..<min(d.count, 514 + 64000)])
            : PackBytes.unpack(d, from: 514, limit: 64000)
        guard pixels.count >= 64000 else { throw FormatError.notThisFormat("an Animator frame file") }
        var image = TrueColorImage(width: 320, height: 200)
        // Colour words are in the original's true colour form: $0RGB plus one extra low bit
        // for each channel in bits 14, 13 and 12.
        let table: [(UInt8, UInt8, UInt8)] = (0..<256).map {
            let w = word(d, $0 * 2)
            func channel(_ high: Int, _ low: Int) -> UInt8 {
                let five = (high & 15) << 1 | (low & 1)
                return UInt8(five << 3 | five >> 2)
            }
            return (channel(w >> 8, w >> 14), channel(w >> 4, w >> 13), channel(w, w >> 12))
        }
        for i in 0..<64000 {
            let c = table[Int(pixels[i])]
            image.setPixel(i % 320, i / 320, c.0, c.1, c.2)
        }
        return image
    }
}

// MARK: - Unix machines

public enum UnixFormats {
    /// Sun Rasterfile: 1, 8, 24 or 32 bits per pixel, optionally run-length encoded.
    public static func loadSunRaster(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 32, longBE(d, 0) == 0x59A6_6A95 else { throw FormatError.notThisFormat("a Sun Rasterfile") }
        let width = longBE(d, 4), height = longBE(d, 8), depth = longBE(d, 12)
        let type = longBE(d, 20), mapType = longBE(d, 24), mapLength = longBE(d, 28)
        guard width > 0, height > 0, width < 32768, height < 32768, [1, 8, 24, 32].contains(depth),
              32 + mapLength <= d.count else { throw FormatError.notThisFormat("a Sun Rasterfile") }
        let lineBytes = ((width * depth + 15) / 16) * 2
        let total = lineBytes * height
        var raw: [UInt8] = []
        var i = 32 + mapLength
        if type == 2 {
            raw.reserveCapacity(total)
            while raw.count < total && i < d.count {
                let b = d[i]
                i += 1
                if b != 0x80 {
                    raw.append(b)
                } else if i < d.count {
                    let n = Int(d[i])
                    i += 1
                    if n == 0 {
                        raw.append(0x80)
                    } else if i < d.count {
                        raw.append(contentsOf: repeatElement(d[i], count: n + 1))
                        i += 1
                    }
                }
            }
        } else {
            raw = Array(d[i..<min(d.count, i + total)])
        }
        raw.append(contentsOf: repeatElement(0, count: max(0, total - raw.count)))
        let entries = mapType == 1 ? mapLength / 3 : 0
        func mapped(_ v: Int) -> (UInt8, UInt8, UInt8) {
            if v < entries { return (d[32 + v], d[32 + entries + v], d[32 + 2 * entries + v]) }
            return (UInt8(v & 255), UInt8(v & 255), UInt8(v & 255))
        }
        var image = TrueColorImage(width: width, height: height)
        let rgbOrder = type == 3
        for y in 0..<height {
            let row = y * lineBytes
            for x in 0..<width {
                switch depth {
                case 1:
                    let set = raw[row + (x >> 3)] & (0x80 >> UInt8(x & 7)) != 0
                    let c = entries >= 2 ? mapped(set ? 1 : 0) : (set ? (0, 0, 0) : (255, 255, 255))
                    image.setPixel(x, y, c.0, c.1, c.2)
                case 8:
                    let c = mapped(Int(raw[row + x]))
                    image.setPixel(x, y, c.0, c.1, c.2)
                default:
                    let at = row + x * (depth / 8) + (depth == 32 ? 1 : 0)
                    if rgbOrder {
                        image.setPixel(x, y, raw[at], raw[at + 1], raw[at + 2])
                    } else {
                        image.setPixel(x, y, raw[at + 2], raw[at + 1], raw[at])
                    }
                }
            }
        }
        return image
    }

    /// SGI Iris: grey or RGB, one or two bytes per channel, stored bottom line first.
    public static func loadSGI(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 512, wordBE(d, 0) == 474 else { throw FormatError.notThisFormat("an SGI Iris picture") }
        let rle = d[2] == 1, bytes = Int(d[3])
        let width = wordBE(d, 6), height = wordBE(d, 8)
        let channels = wordBE(d, 4) < 3 ? 1 : wordBE(d, 10)
        guard width > 0, height > 0, (1...2).contains(bytes), channels > 0 else {
            throw FormatError.notThisFormat("an SGI Iris picture")
        }
        func row(_ y: Int, _ channel: Int) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: width)
            if !rle {
                let at = 512 + (channel * height + y) * width * bytes
                for x in 0..<width where at + x * bytes < d.count { out[x] = d[at + x * bytes] }
                return out
            }
            let entry = 512 + (channel * height + y) * 4
            guard entry + 4 <= d.count else { return out }
            var i = longBE(d, entry)
            var x = 0
            while x < width && i < d.count {
                let control = bytes == 2 && i + 1 < d.count ? d[i + 1] : d[i]
                i += bytes
                let n = Int(control & 0x7F)
                if n == 0 { break }
                if control & 0x80 != 0 {
                    for _ in 0..<n where i < d.count {
                        if x < width { out[x] = d[i] }
                        x += 1
                        i += bytes
                    }
                } else if i < d.count {
                    for _ in 0..<n {
                        if x < width { out[x] = d[i] }
                        x += 1
                    }
                    i += bytes
                }
            }
            return out
        }
        var image = TrueColorImage(width: width, height: height)
        for y in 0..<height {
            let r = row(y, 0)
            let g = channels >= 3 ? row(y, 1) : r
            let b = channels >= 3 ? row(y, 2) : r
            for x in 0..<width { image.setPixel(x, height - 1 - y, r[x], g[x], b[x]) }
        }
        return image
    }

    /// Portable bitmap, greymap and pixmap (.PBM, .PGM, .PPM), text or binary.
    public static func loadPNM(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count > 3, d[0] == 0x50, (0x31...0x36).contains(d[1]) else {
            throw FormatError.notThisFormat("a Portable Pixelmap")
        }
        let kind = Int(d[1] - 0x30)
        var i = 2
        func number() -> Int? {
            while i < d.count {
                if d[i] == 0x23 {
                    while i < d.count && d[i] != 0x0A { i += 1 }
                } else if d[i] <= 0x20 {
                    i += 1
                } else {
                    break
                }
            }
            var v = 0
            var any = false
            while i < d.count, d[i] >= 0x30, d[i] <= 0x39 {
                v = v * 10 + Int(d[i] - 0x30)
                i += 1
                any = true
            }
            return any ? v : nil
        }
        guard let width = number(), let height = number(), width > 0, height > 0 else {
            throw FormatError.notThisFormat("a Portable Pixelmap")
        }
        let top = kind == 1 || kind == 4 ? 1 : max(1, number() ?? 255)
        var image = TrueColorImage(width: width, height: height)
        func scale(_ v: Int) -> UInt8 { UInt8(min(255, v * 255 / top)) }
        if kind <= 3 {
            for y in 0..<height {
                for x in 0..<width {
                    if kind == 1 {
                        // Digits may run together in plain bitmaps.
                        while i < d.count && d[i] != 0x30 && d[i] != 0x31 { i += 1 }
                        let ink = i < d.count && d[i] == 0x31
                        i += 1
                        image.setPixel(x, y, ink ? 0 : 255, ink ? 0 : 255, ink ? 0 : 255)
                    } else if kind == 2 {
                        let g = scale(number() ?? 0)
                        image.setPixel(x, y, g, g, g)
                    } else {
                        image.setPixel(x, y, scale(number() ?? 0), scale(number() ?? 0), scale(number() ?? 0))
                    }
                }
            }
            return image
        }
        i += 1      // the single whitespace byte after the header
        let wide = top > 255
        func sample() -> UInt8 {
            guard i < d.count else { return 0 }
            if wide {
                let v = i + 1 < d.count ? wordBE(d, i) : 0
                i += 2
                return scale(v)
            }
            i += 1
            return scale(Int(d[i - 1]))
        }
        for y in 0..<height {
            if kind == 4 {
                let row = i
                for x in 0..<width {
                    let ink = row + (x >> 3) < d.count && d[row + (x >> 3)] & (0x80 >> UInt8(x & 7)) != 0
                    image.setPixel(x, y, ink ? 0 : 255, ink ? 0 : 255, ink ? 0 : 255)
                }
                i += (width + 7) / 8
            } else {
                for x in 0..<width {
                    if kind == 5 {
                        let g = sample()
                        image.setPixel(x, y, g, g, g)
                    } else {
                        image.setPixel(x, y, sample(), sample(), sample())
                    }
                }
            }
        }
        return image
    }
}
