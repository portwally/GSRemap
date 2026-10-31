import Foundation

// Formats MegaconvertGS added to SuperConvert's lists (its src/CPC.s, MSX.s, ZX.s, Atari8.s,
// OtherPC.s, Apple.s), with the same colours, so both give the same pixels.

/// The Super Hi-Res colour of 3-bit red, green and blue (MSX), and of 0-255 levels.
@inline(__always) func rgb12(_ r: Int, _ g: Int, _ b: Int) -> Color12 { Color12(r << 8 | g << 4 | b) }

// MARK: - Commodore 64: Art Studio, Advanced Art Studio, FLI Graph, Amica Paint

extension C64Formats {
    /// Art Studio (OCP) hires, also Interpaint and others without its last bytes: load
    /// address, 8000 bitmap bytes, 1000 screen bytes (ink in the high nibble).
    public static func loadArtStudio(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 9002 else { throw FormatError.notThisFormat("an Art Studio picture") }
        return hires(bitmap: d[2..<8002]) { d[8002 + $0] }
    }

    /// Multicolour: four colour choices per 4 x 8 cell (background, screen high and low
    /// nibble, colour memory), 160 pixels twice as wide.
    static func multicolour(bitmap: (Int) -> UInt8, screen: (Int) -> UInt8, colour: (Int) -> UInt8,
                            background: UInt8, blackColumns: Int = 0) -> ScreenImage {
        var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [palette])
        for y in 0..<200 {
            for x in 0..<160 {
                var value: UInt8 = 0
                if x >= blackColumns {
                    let cell = (y >> 3) * 40 + (x >> 2)
                    let pair = (bitmap(cell * 8 + (y & 7)) >> UInt8(6 - 2 * (x & 3))) & 3
                    switch pair {
                    case 0: value = background
                    case 1: value = screen(cell) >> 4
                    case 2: value = screen(cell) & 15
                    default: value = colour(cell) & 15
                    }
                }
                s.pixels[y * 320 + x * 2] = value
                s.pixels[y * 320 + x * 2 + 1] = value
            }
        }
        return s
    }

    /// Advanced Art Studio (OCP): load address, bitmap, screen, border, background, 14
    /// unused bytes, colour memory (10018 bytes).
    public static func loadAdvancedArtStudio(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 10018 else { throw FormatError.notThisFormat("an Advanced Art Studio picture") }
        return multicolour(bitmap: { d[2 + $0] }, screen: { d[8002 + $0] }, colour: { d[9018 + $0] },
                           background: d[9003] & 15)
    }

    /// FLI Graph: load address, colour memory (1000), then 8 screens of 1024 bytes (one for
    /// each line of a cell), then the bitmap at $2402; background black. The first three
    /// columns, which the C64 can't show, are black.
    public static func loadFLI(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 17409 else { throw FormatError.notThisFormat("a FLI Graph picture") }
        var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [palette])
        for y in 0..<200 {
            for x in 0..<160 {
                var value: UInt8 = 0
                if x >= 12 {
                    let cell = (y >> 3) * 40 + (x >> 2)
                    let pair = (d[0x2402 + cell * 8 + (y & 7)] >> UInt8(6 - 2 * (x & 3))) & 3
                    let scr = d[0x402 + (y & 7) * 1024 + cell]
                    switch pair {
                    case 0: value = 0
                    case 1: value = scr >> 4
                    case 2: value = scr & 15
                    default: value = d[2 + cell] & 15
                    }
                }
                s.pixels[y * 320 + x * 2] = value
                s.pixels[y * 320 + x * 2 + 1] = value
            }
        }
        return s
    }

    /// Amica Paint: a Koala picture packed after its load address: $C2, count, byte for a
    /// run; any other byte as it is.
    public static func loadAmica(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count > 2 else { throw FormatError.notThisFormat("an Amica Paint picture") }
        var o: [UInt8] = []
        var i = 2
        while i < d.count && o.count < 10001 {
            if d[i] == 0xC2 {
                guard i + 2 < d.count else { break }
                let n = Int(d[i + 1]) == 0 ? 256 : Int(d[i + 1])
                o += [UInt8](repeating: d[i + 2], count: n); i += 3
            } else { o.append(d[i]); i += 1 }
        }
        guard o.count >= 10001 else { throw FormatError.notThisFormat("an Amica Paint picture") }
        return multicolour(bitmap: { o[$0] }, screen: { o[8000 + $0] }, colour: { o[9000 + $0] },
                           background: o[10000] & 15)
    }
}

// MARK: - ZX Spectrum

public enum ZXFormats {
    /// Ink and paper 0-7, then the bright ones (MegaconvertGS's Super Hi-Res colours).
    public static let palette: [Color12] = [
        0x000, 0x00D, 0xD00, 0xD0D, 0x0D0, 0x0DD, 0xDD0, 0xDDD,
        0x000, 0x00F, 0xF00, 0xF0F, 0x0F0, 0x0FF, 0xFF0, 0xFFF,
    ]

    /// 6912 bytes: the bitmap in the Spectrum's order, then a colour cell for each 8 x 8
    /// (ink, paper, bright; flash left out); 6144 bytes without colours: black on white.
    public static func loadScreen(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 6144 else { throw FormatError.notThisFormat("a ZX Spectrum screen") }
        var s = ScreenImage(width: 256, height: 192, is640: false, palettes: [palette])
        for y in 0..<192 {
            for x in 0..<256 {
                let at = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)
                let bit = d[at] >> UInt8(7 - (x & 7)) & 1
                let attr = d.count >= 6912 ? d[6144 + (y >> 3) * 32 + (x >> 3)] : 0x38
                var i = bit != 0 ? attr & 7 : (attr >> 3) & 7
                if attr & 0x40 != 0 { i += 8 }
                s.pixels[y * 256 + x] = i
            }
        }
        return s
    }
}

// MARK: - MSX

public enum MSXFormats {
    static let levels = [0, 36, 73, 109, 146, 182, 219, 255]
    /// Screen 2's colours (TMS9918) as Super Hi-Res colours.
    public static let palette1: [Color12] = [
        0x000, 0x000, 0x2D2, 0x6F6, 0x22F, 0x46F, 0xB22, 0x4DF,
        0xF22, 0xF66, 0xDD2, 0xDD9, 0x292, 0xD4B, 0xBBB, 0xFFF,
    ]
    /// The MSX2's colours at start-up (3 bits each), for files without a palette.
    static let defaultPalette: [(Int, Int, Int)] = [
        (0, 0, 0), (0, 0, 0), (1, 6, 1), (3, 7, 3), (1, 1, 7), (2, 3, 7), (5, 1, 1), (2, 6, 7),
        (7, 1, 1), (7, 3, 3), (6, 6, 1), (6, 6, 4), (1, 4, 1), (6, 2, 5), (5, 5, 5), (7, 7, 7),
    ]

    /// A BSAVE file ($FE, start, end, run address) as 64K of video memory.
    static func vram(_ d: [UInt8]) throws -> (memory: [UInt8], end: Int) {
        guard d.count > 7, d[0] == 0xFE else { throw FormatError.notThisFormat("an MSX BSAVE file") }
        let start = word(d, 1), end = word(d, 3)
        var m = [UInt8](repeating: 0, count: 0x10000)
        let n = min(d.count - 7, 0x10000 - start)
        if n > 0 { m.replaceSubrange(start..<(start + n), with: d[7..<(7 + n)]) }
        return (m, start + n - 1)
    }

    /// Screen 2: 256 x 192, patterns and colours in three thirds, a name table.
    public static func loadScreen2(_ d: [UInt8]) throws -> ScreenImage {
        let m = try vram(d).memory
        var s = ScreenImage(width: 256, height: 192, is640: false, palettes: [palette1])
        for y in 0..<192 {
            let t = y >> 6, l = y & 7
            for x in 0..<256 {
                let name = Int(m[0x1800 + (y >> 3) * 32 + (x >> 3)])
                let bits = m[t * 2048 + name * 8 + l], col = m[0x2000 + t * 2048 + name * 8 + l]
                s.pixels[y * 256 + x] = bits >> UInt8(7 - (x & 7)) & 1 != 0 ? col >> 4 : col & 15
            }
        }
        return s
    }

    /// Screens 5 and 7: 4 bits a pixel (256 or 512 x 212), the palette from video memory
    /// when the file holds it, else the MSX2's own.
    static func nibbles(_ d: [UInt8], width: Int, paletteAt: Int) throws -> TrueColorImage {
        let (m, end) = try vram(d)
        var pal = defaultPalette
        if end >= paletteAt + 31 {
            pal = (0..<16).map { i in (Int(m[paletteAt + 2 * i] >> 4) & 7, Int(m[paletteAt + 2 * i + 1]) & 7, Int(m[paletteAt + 2 * i]) & 7) }
        }
        var t = TrueColorImage(width: width, height: 212, tallPixels: width == 512)
        let per = width / 2
        for y in 0..<212 {
            for x in 0..<width {
                let v = m[y * per + x / 2]
                let (r, g, b) = pal[Int(x % 2 == 0 ? v >> 4 : v & 15)]
                let at = (y * width + x) * 3
                t.rgb[at] = UInt8(levels[r]); t.rgb[at + 1] = UInt8(levels[g]); t.rgb[at + 2] = UInt8(levels[b])
            }
        }
        return t
    }
    public static func loadScreen5(_ d: [UInt8]) throws -> TrueColorImage { try nibbles(d, width: 256, paletteAt: 0x7680) }
    public static func loadScreen7(_ d: [UInt8]) throws -> TrueColorImage { try nibbles(d, width: 512, paletteAt: 0xFA80) }

    /// Screen 8: 256 x 212, a byte a pixel: green (3 bits), red (3 bits), blue (2 bits).
    public static func loadScreen8(_ d: [UInt8]) throws -> TrueColorImage {
        let m = try vram(d).memory
        var t = TrueColorImage(width: 256, height: 212)
        for i in 0..<(256 * 212) {
            let v = Int(m[i])
            t.rgb[i * 3] = UInt8(levels[(v >> 2) & 7])
            t.rgb[i * 3 + 1] = UInt8(levels[v >> 5])
            t.rgb[i * 3 + 2] = UInt8([0, 85, 170, 255][v & 3])
        }
        return t
    }
}

// MARK: - Amstrad CPC

public enum CPCFormats {
    /// The 16 inks' colours at start-up.
    static let startColours: [Color12] = [
        0x008, 0xFF0, 0x0FF, 0xF00, 0xFFF, 0x000, 0x00F, 0xF0F,
        0x088, 0x880, 0x88F, 0xF88, 0x0F0, 0x8F8, 0x008, 0xF88,
    ]
    /// The 32 hardware colours (a .PAL file's ink values, $40 + n).
    static let hardware: [Color12] = [
        0x888, 0x888, 0x0F8, 0xFF8, 0x008, 0xF08, 0x088, 0xF88, 0xF08, 0xFF8, 0xFF0, 0xFFF, 0xF00, 0xF0F,
        0xF80, 0xF8F, 0x008, 0x0F8, 0x0F0, 0x0FF, 0x000, 0x00F, 0x080, 0x08F, 0x808, 0x8F8, 0x8F0, 0x8FF,
        0x800, 0x80F, 0x880, 0x88F,
    ]

    /// The 16K of screen memory: as it is, after a 128-byte AMSDOS header (known by its
    /// checksum), or packed by OCP Art Studio (blocks "MJH", length, then 1, count, byte
    /// for a run and any other byte as it is).
    static func memory(_ d: [UInt8]) throws -> [UInt8] {
        if d.count >= 3, d[0] == 0x4D, d[1] == 0x4A, d[2] == 0x48 {
            var o: [UInt8] = []
            var i = 0
            while i + 5 <= d.count, d[i] == 0x4D, d[i + 1] == 0x4A, d[i + 2] == 0x48, o.count < 16384 {
                let length = word(d, i + 3)
                var block: [UInt8] = []
                i += 5
                while block.count < length && i < d.count {
                    if d[i] == 1, i + 2 < d.count {
                        let n = d[i + 1] == 0 ? 256 : Int(d[i + 1])
                        block += [UInt8](repeating: d[i + 2], count: n); i += 3
                    } else { block.append(d[i]); i += 1 }
                }
                o += block.prefix(length)
            }
            return o + [UInt8](repeating: 0, count: max(0, 16384 - o.count))
        }
        if d.count >= 128 + 16000 {
            let sum = d[0..<67].reduce(0) { $0 + Int($1) } & 0xFFFF
            if sum == word(d, 67) && sum != 0 { return Array(d[128...]) + [UInt8](repeating: 0, count: max(0, 16384 + 128 - d.count)) }
        }
        guard d.count >= 16000 else { throw FormatError.notThisFormat("an Amstrad CPC screen") }
        return d + [UInt8](repeating: 0, count: max(0, 16384 - d.count))
    }

    /// OCP Art Studio's .PAL beside the screen: mode, then 16 inks of 12 bytes ($40 + colour).
    static func palFile(beside url: URL) -> (mode: Int, inks: [Color12])? {
        let pal = url.deletingPathExtension().appendingPathExtension("PAL")
        let alt = url.deletingPathExtension().appendingPathExtension("pal")
        guard let p = (try? Data(contentsOf: pal)) ?? (try? Data(contentsOf: alt)) else { return nil }
        let d = [UInt8](p)
        guard d.count >= 3 + 16 * 12, d[0] <= 2 else { return nil }
        return (Int(d[0]), (0..<16).map { hardware[Int(d[3 + $0 * 12]) & 31] })
    }

    /// A screen in mode 0 (160 x 200, 16 colours, pixels twice as wide), 1 (320 x 200, 4)
    /// or 2 (640 x 200, 2); the mode and colours from a .PAL file beside it, if any.
    public static func load(_ url: URL, mode chosen: Int) throws -> ScreenImage {
        let m = try memory([UInt8](try Data(contentsOf: url)))
        var mode = chosen, colours = startColours
        if let pal = palFile(beside: url) { mode = pal.mode; colours = pal.inks }
        func line(_ y: Int) -> Int { (y & 7) * 2048 + (y >> 3) * 80 }
        if mode == 2 {
            // 640 mode: every pixel's palette group holds ink 0 and ink 1.
            let table = (0..<16).map { colours[$0 & 1] }
            var s = ScreenImage(width: 640, height: 200, is640: true, palettes: [table])
            for y in 0..<200 {
                for xb in 0..<80 {
                    let b = m[line(y) + xb]
                    for k in 0..<8 { s.pixels[y * 640 + xb * 8 + k] = b >> UInt8(7 - k) & 1 }
                }
            }
            return s
        }
        var s = ScreenImage(width: 320, height: 200, is640: false, palettes: [Array(colours.prefix(16))])
        for y in 0..<200 {
            for xb in 0..<80 {
                let b = Int(m[line(y) + xb])
                if mode == 0 {
                    for sh in 0..<2 {
                        let v = (b << sh) & 255
                        let i = (v >> 7 & 1) | (v >> 3 & 1) << 1 | (v >> 5 & 1) << 2 | (v >> 1 & 1) << 3
                        s.pixels[y * 320 + xb * 4 + sh * 2] = UInt8(i)
                        s.pixels[y * 320 + xb * 4 + sh * 2 + 1] = UInt8(i)
                    }
                } else {
                    for k in 0..<4 {
                        s.pixels[y * 320 + xb * 4 + k] = UInt8((b >> (7 - k) & 1) | (b >> (3 - k) & 1) << 1)
                    }
                }
            }
        }
        return s
    }
}

// MARK: - Atari 8-bit

public enum Atari8Formats {
    /// The Atari's 256 colours by register value (MegaconvertGS's A8Pal, from
    /// test/make_atari8_pal.py: an approximation of the NTSC GTIA).
    public static let palette: [Color12] = [
        0x000, 0x000, 0x222, 0x222, 0x444, 0x444, 0x666, 0x666,
        0x999, 0x999, 0xBBB, 0xBBB, 0xDDD, 0xDDD, 0xFFF, 0xFFF,
        0x210, 0x210, 0x541, 0x541, 0x862, 0x862, 0xB83, 0xB83,
        0xCA4, 0xCA4, 0xDB7, 0xDB7, 0xEDA, 0xEDA, 0xFED, 0xFED,
        0x210, 0x210, 0x521, 0x521, 0x832, 0x832, 0xB53, 0xB53,
        0xC74, 0xC74, 0xD97, 0xD97, 0xEBA, 0xEBA, 0xFDD, 0xFDD,
        0x201, 0x201, 0x512, 0x512, 0x823, 0x823, 0xB34, 0xB34,
        0xC45, 0xC45, 0xD78, 0xD78, 0xEAB, 0xEAB, 0xFDD, 0xFDD,
        0x201, 0x201, 0x513, 0x513, 0x825, 0x825, 0xB37, 0xB37,
        0xC49, 0xC49, 0xD7A, 0xD7A, 0xEAC, 0xEAC, 0xFDE, 0xFDE,
        0x202, 0x202, 0x515, 0x515, 0x827, 0x827, 0xB3A, 0xB3A,
        0xC4C, 0xC4C, 0xD7D, 0xD7D, 0xEAE, 0xEAE, 0xFDE, 0xFDE,
        0x102, 0x102, 0x415, 0x415, 0x628, 0x628, 0x83B, 0x83B,
        0xA4C, 0xA4C, 0xB7D, 0xB7D, 0xDAE, 0xDAE, 0xEDF, 0xEDF,
        0x102, 0x102, 0x215, 0x215, 0x328, 0x328, 0x53B, 0x53B,
        0x74C, 0x74C, 0x97D, 0x97D, 0xBAE, 0xBAE, 0xDDF, 0xDDF,
        0x012, 0x012, 0x125, 0x125, 0x238, 0x238, 0x34B, 0x34B,
        0x45C, 0x45C, 0x78D, 0x78D, 0xABE, 0xABE, 0xDDF, 0xDDF,
        0x012, 0x012, 0x135, 0x135, 0x258, 0x258, 0x37B, 0x37B,
        0x49C, 0x49C, 0x7AD, 0x7AD, 0xACE, 0xACE, 0xDEF, 0xDEF,
        0x022, 0x022, 0x155, 0x155, 0x278, 0x278, 0x3AB, 0x3AB,
        0x4CC, 0x4CC, 0x7DD, 0x7DD, 0xAEE, 0xAEE, 0xDEF, 0xDEF,
        0x021, 0x021, 0x154, 0x154, 0x286, 0x286, 0x3B8, 0x3B8,
        0x4CA, 0x4CA, 0x7DB, 0x7DB, 0xAED, 0xAED, 0xDFE, 0xDFE,
        0x021, 0x021, 0x152, 0x152, 0x283, 0x283, 0x3B5, 0x3B5,
        0x4C7, 0x4C7, 0x7D9, 0x7D9, 0xAEB, 0xAEB, 0xDFD, 0xDFD,
        0x120, 0x120, 0x251, 0x251, 0x382, 0x382, 0x4B3, 0x4B3,
        0x5C4, 0x5C4, 0x8D7, 0x8D7, 0xBEA, 0xBEA, 0xDFD, 0xDFD,
        0x120, 0x120, 0x351, 0x351, 0x582, 0x582, 0x7B3, 0x7B3,
        0x9C4, 0x9C4, 0xAD7, 0xAD7, 0xCEA, 0xCEA, 0xEFD, 0xEFD,
        0x220, 0x220, 0x551, 0x551, 0x782, 0x782, 0xAB3, 0xAB3,
        0xCC4, 0xCC4, 0xDD7, 0xDD7, 0xEEA, 0xEEA, 0xEFD, 0xEFD,
    ]

    static func lines(_ d: [UInt8]) throws -> Int {
        guard d.count >= 7680 else { throw FormatError.notThisFormat("an Atari 8-bit screen") }
        return 192
    }

    /// MicroPainter: 160 x 192 in 4 colours (pixels twice as wide); the colour registers
    /// (background, playfield 0-2) after the picture, else greys.
    public static func loadMicroPainter(_ d: [UInt8]) throws -> ScreenImage {
        _ = try lines(d)
        let regs = d.count >= 7684 ? Array(d[7680..<7684]) : [0x00, 0x04, 0x08, 0x0C]
        let table = (0..<16).map { palette[Int(regs[$0 & 3])] }
        var s = ScreenImage(width: 320, height: 192, is640: false, palettes: [table])
        for y in 0..<192 {
            for xb in 0..<40 {
                let b = d[y * 40 + xb]
                for k in 0..<4 {
                    let v = b >> UInt8(6 - 2 * k) & 3
                    s.pixels[y * 320 + xb * 8 + k * 2] = v
                    s.pixels[y * 320 + xb * 8 + k * 2 + 1] = v
                }
            }
        }
        return s
    }

    /// Graphics 8: 320 x 192, white dots on black.
    public static func loadGraphics8(_ d: [UInt8]) throws -> ScreenImage {
        _ = try lines(d)
        var table = [Color12](repeating: 0x000, count: 16); table[1] = 0xFFF
        var s = ScreenImage(width: 320, height: 192, is640: false, palettes: [table])
        for i in 0..<(320 * 192) { s.pixels[i] = d[i >> 3] >> UInt8(7 - (i & 7)) & 1 }
        return s
    }

    /// Graphics 9: 80 x 192 in 16 greys, each pixel four wide.
    public static func loadGraphics9(_ d: [UInt8]) throws -> ScreenImage {
        _ = try lines(d)
        let table = (0..<16).map { Color12(0x111 * $0) }
        var s = ScreenImage(width: 320, height: 192, is640: false, palettes: [table])
        for y in 0..<192 {
            for x in 0..<320 {
                s.pixels[y * 320 + x] = d[y * 40 + x / 8] >> UInt8(x % 8 < 4 ? 4 : 0) & 15
            }
        }
        return s
    }
}

// MARK: - Apple II LoRes and Double LoRes

extension AppleIIFormats {
    /// LoRes colours in the screen's colour numbers.
    public static let loResPalette: [Color12] = [
        0x000, 0xD03, 0x009, 0xD0D, 0x070, 0x555, 0x22F, 0x6AF,
        0x852, 0xF60, 0xAAA, 0xF98, 0x0D0, 0xFF0, 0x0F9, 0xFFF,
    ]

    /// The text page as 40 x 48 blocks (Double LoRes: 80, its auxiliary columns' bits
    /// turned right by one), shown 280 x 192: a block 7 x 4 (Double: 3 or 4 across).
    public static func loadLoRes(_ d: [UInt8], double: Bool) throws -> ScreenImage {
        guard d.count >= (double ? 2048 : 1024) - 8 else {
            throw FormatError.notThisFormat(double ? "an Apple II Double LoRes screen" : "an Apple II LoRes screen")
        }
        let cols = double ? 80 : 40
        func at(_ t: Int) -> Int { (t & 7) * 128 + (t >> 3) * 40 }
        var blocks = [[UInt8]](repeating: [UInt8](repeating: 0, count: cols), count: 48)
        for by in 0..<48 {
            for bx in 0..<cols {
                var a = at(by >> 1) + (double ? bx >> 1 : bx)
                if double && bx & 1 != 0 { a += 1024 }
                var c = a < d.count ? (d[a] >> UInt8(by & 1 != 0 ? 4 : 0)) & 15 : 0
                if double && bx & 1 == 0 { c = ((c << 1) | (c >> 3)) & 15 }
                blocks[by][bx] = c
            }
        }
        var s = ScreenImage(width: 280, height: 192, is640: false, palettes: [loResPalette])
        let ends = (0..<cols).map { (7 * ($0 + 1)) / (double ? 2 : 1) }
        for y in 0..<192 {
            var k = 0
            for x in 0..<280 {
                while x >= ends[k] { k += 1 }
                s.pixels[y * 280 + x] = blocks[y >> 2][k]
            }
        }
        return s
    }
}
