import Foundation

// Truevision Targa and Macintosh QuickDraw pictures, as MegaconvertGS reads them
// (its src/TGA.s and src/PICT.s): true colour pictures.

public enum TGAFormat {
    @inline(__always) static func five(_ v: Int) -> UInt8 { UInt8((v << 3) | (v >> 2)) }

    /// Types 1, 2, 3 (colour-mapped, true colour, grey) and 9, 10, 11 (the same run-length
    /// coded); 8, 15, 16, 24 or 32 bits a pixel; colour maps of 15, 16, 24 or 32 bits an
    /// entry; rows from the bottom (or top, descriptor bit 5), each from the left (or right,
    /// bit 4). The alpha channel is left out.
    public static func load(_ d: [UInt8]) throws -> TrueColorImage {
        guard d.count >= 18 else { throw FormatError.notThisFormat("a Targa picture") }
        let idLength = Int(d[0]), mapType = d[1], kind = Int(d[2])
        let mapFirst = word(d, 3), mapLength = word(d, 5), mapBits = Int(d[7])
        let w = word(d, 12), h = word(d, 14), bits = Int(d[16]), desc = d[17]
        let base = kind & 7, rle = kind & 8 != 0
        guard [1, 2, 3].contains(base), w > 0, h > 0, w <= 4096, h <= 4096,
              base != 1 || (mapType == 1 && bits == 8), base != 3 || bits == 8,
              base != 2 || [15, 16, 24, 32].contains(bits) else {
            throw FormatError.notThisFormat("a Targa picture")
        }
        func colour(_ p: Int, _ size: Int) -> (UInt8, UInt8, UInt8) {
            switch size {
            case 15, 16:
                let v = word(d, p)
                return (five(v >> 10 & 31), five(v >> 5 & 31), five(v & 31))
            default: return (d[p + 2], d[p + 1], d[p])
            }
        }
        var at = 18 + idLength
        var map: [(UInt8, UInt8, UInt8)] = []
        if mapType == 1 {
            let entry = (mapBits + 7) / 8
            guard at + mapLength * entry <= d.count else { throw FormatError.notThisFormat("a Targa picture") }
            map = (0..<mapLength).map { colour(at + $0 * entry, mapBits) }
            at += mapLength * entry
        }
        let size = (bits + 7) / 8
        var t = TrueColorImage(width: w, height: h)
        func put(_ i: Int, _ p: Int) {
            let n = i / w, x0 = i % w
            let y = desc & 0x20 != 0 ? n : h - 1 - n
            let x = desc & 0x10 != 0 ? w - 1 - x0 : x0
            let c: (UInt8, UInt8, UInt8)
            switch base {
            case 1:
                let v = Int(d[p]) - mapFirst
                c = v >= 0 && v < map.count ? map[v] : (0, 0, 0)
            case 3: c = (d[p], d[p], d[p])
            default: c = colour(p, bits)
            }
            let o = (y * w + x) * 3
            t.rgb[o] = c.0; t.rgb[o + 1] = c.1; t.rgb[o + 2] = c.2
        }
        var i = 0
        if !rle {
            while i < w * h && at + size <= d.count { put(i, at); at += size; i += 1 }
        } else {
            while i < w * h && at < d.count {
                let head = Int(d[at]); at += 1
                let n = (head & 0x7F) + 1
                if head & 0x80 != 0 {
                    guard at + size <= d.count else { break }
                    for _ in 0..<n where i < w * h { put(i, at); i += 1 }
                    at += size
                } else {
                    for _ in 0..<n where i < w * h && at + size <= d.count { put(i, at); at += size; i += 1 }
                }
            }
        }
        return t
    }
}

public enum PICTFormat {
    struct Rect { var top, left, bottom, right: Int
        var width: Int { right - left }; var height: Int { bottom - top } }

    /// Version 1 and 2 pictures, with or without the 512 bytes a Mac file starts with. The bit
    /// maps and pixel maps in them are drawn (BitsRect, PackBitsRect, DirectBitsRect, and the
    /// same through a region): 1, 2, 4 or 8 bits a pixel through a colour table, 16 or 32 bits
    /// a pixel; the other commands are passed over. Each image goes where the picture puts it;
    /// when the first is drawn at another size, the whole picture is made that much bigger, so
    /// the pixels stay as they are. What no image covers is white.
    public static func load(_ d: [UInt8]) throws -> TrueColorImage {
        for start in [0, 512] where start + 14 <= d.count {
            if d[start + 10] == 0x11 && d[start + 11] == 0x01 { return try parse(d, start, v2: false) }
            if d[start + 10] == 0x00 && d[start + 11] == 0x11 && d[start + 12] == 0x02 && d[start + 13] == 0xFF {
                return try parse(d, start, v2: true)
            }
        }
        throw FormatError.notThisFormat("a QuickDraw picture")
    }

    static func rect(_ d: [UInt8], _ p: Int) -> Rect {
        Rect(top: Int(Int16(truncatingIfNeeded: wordBE(d, p))), left: Int(Int16(truncatingIfNeeded: wordBE(d, p + 2))),
             bottom: Int(Int16(truncatingIfNeeded: wordBE(d, p + 4))), right: Int(Int16(truncatingIfNeeded: wordBE(d, p + 6))))
    }

    /// A 16-bit colour component to 8 bits, rounded: v / 257 (MegaconvertGS's PcTo8).
    @inline(__always) static func to8(_ v: Int) -> UInt8 {
        if v >= 0xFF7F { return 255 }
        let x = v + 128
        return UInt8((x - (x >> 8)) >> 8)
    }

    static func unpackBits(_ d: [UInt8], _ p: Int, _ count: Int, unit: Int) -> [UInt8] {
        var o: [UInt8] = [], i = p
        let end = min(d.count, p + count)
        while i < end {
            let f = Int(Int8(truncatingIfNeeded: d[i])); i += 1
            if f >= 0 {
                let n = (f + 1) * unit
                o += d[i..<min(end, i + n)]; i += n
            } else if f != -128 {
                let item = Array(d[i..<min(end, i + unit)]); i += unit
                for _ in 0..<(1 - f) { o += item }
            }
        }
        return o
    }

    static func parse(_ d: [UInt8], _ start: Int, v2: Bool) throws -> TrueColorImage {
        let frame = rect(d, start + 2)
        guard frame.width > 0, frame.height > 0 else { throw FormatError.notThisFormat("a QuickDraw picture") }
        var canvas: TrueColorImage?
        var scale = (nx: 1, dx: 1, ny: 1, dy: 1)
        var p = start + 10
        func need(_ n: Int) throws { if p + n > d.count { throw FormatError.notThisFormat("a QuickDraw picture") } }
        while p < d.count {
            if v2 && (p - start) & 1 != 0 { p += 1 }
            try need(v2 ? 2 : 1)
            let op = v2 ? wordBE(d, p) : Int(d[p]); p += v2 ? 2 : 1
            switch op {
            case 0xFF, 0x00FF: p = d.count
            case 0x90, 0x91, 0x98, 0x99, 0x9A, 0x9B:
                let (img, src, dst, bounds, next) = try image(d, p, op: op)
                p = next
                if canvas == nil {
                    scale = (max(1, src.width), max(1, dst.width), max(1, src.height), max(1, dst.height))
                    let w = frame.width * scale.nx / scale.dx, h = frame.height * scale.ny / scale.dy
                    guard w > 0, h > 0, w <= 4096, h <= 4096 else { throw FormatError.unsupported("The picture is too large.") }
                    canvas = TrueColorImage(width: w, height: h, rgb: [UInt8](repeating: 255, count: w * h * 3))
                }
                let ox = (dst.left - frame.left) * scale.nx / scale.dx + bounds.left - src.left
                let oy = (dst.top - frame.top) * scale.ny / scale.dy + bounds.top - src.top
                for j in 0..<bounds.height {
                    let by = bounds.top + j
                    guard by >= src.top && by < src.bottom else { continue }
                    let Y = j + oy
                    guard Y >= 0 && Y < canvas!.height else { continue }
                    for i in 0..<bounds.width {
                        let bx = bounds.left + i
                        guard bx >= src.left && bx < src.right else { continue }
                        let X = i + ox
                        guard X >= 0 && X < canvas!.width else { continue }
                        let s = (j * bounds.width + i) * 3, o = (Y * canvas!.width + X) * 3
                        canvas!.rgb[o] = img[s]; canvas!.rgb[o + 1] = img[s + 1]; canvas!.rgb[o + 2] = img[s + 2]
                    }
                }
            default:
                p += try skip(d, p, op: op, v2: v2)
            }
        }
        guard let result = canvas else { throw FormatError.unsupported("The picture has no bit map or pixel map in it.") }
        return result
    }

    /// The length of a command's data (not drawn), from QuickDraw's list.
    static func skip(_ d: [UInt8], _ p: Int, op: Int, v2: Bool) throws -> Int {
        func w(_ o: Int) -> Int { p + o + 1 < d.count ? wordBE(d, p + o) : 0 }
        func b(_ o: Int) -> Int { p + o < d.count ? Int(d[p + o]) : 0 }
        func l(_ o: Int) -> Int { p + o + 3 < d.count ? longBE(d, p + o) : 0 }
        switch op {
        case 0x00, 0x1C, 0x1E, 0x17...0x19: return 0
        case 0x01: return w(0)
        case 0x02, 0x09, 0x0A, 0x10: return 8
        case 0x03, 0x05, 0x08, 0x0D, 0x15, 0x16, 0x23: return 2
        case 0x04: return 1
        case 0x06, 0x07, 0x0B, 0x0C, 0x0E, 0x0F, 0x21: return 4
        case 0x11: return v2 ? 2 : 1
        case 0x1A, 0x1B, 0x1D, 0x1F, 0x22: return 6
        case 0x20: return 8
        case 0x24...0x27, 0x2C...0x2F: return 2 + w(0)
        case 0x28: return 5 + b(4)
        case 0x29, 0x2A: return 2 + b(1)
        case 0x2B: return 3 + b(2)
        case 0x30...0x37, 0x40...0x47, 0x50...0x57: return 8
        case 0x38...0x3F, 0x48...0x4F, 0x58...0x5F, 0x78...0x7F, 0x88...0x8F: return 0
        case 0x60...0x67: return 12
        case 0x68...0x6F: return 4
        case 0x70...0x77, 0x80...0x87: return w(0)
        case 0x9C...0x9F, 0xA2...0xAF: return 2 + w(0)
        case 0xA0: return 2
        case 0xA1: return 4 + w(2)
        case 0xB0...0xCF: return 0
        case 0xD0...0xFE: return 4 + l(0)
        case 0x0C00: return 24
        case 0x02FF: return 2
        case 0x0100...0x7FFF: return (op >> 8) * 2
        case 0x8000...0x80FF: return 0
        case 0x8100...0xFFFF: return 4 + l(0)
        default: throw FormatError.unsupported(String(format: "QuickDraw command $%04X isn't read.", op))
        }
    }

    /// A bit map or pixel map command: its pixels (RGB, the bounds' size), the source and
    /// destination rectangles, its bounds, and where the next command starts.
    static func image(_ d: [UInt8], _ start: Int, op: Int) throws -> ([UInt8], Rect, Rect, Rect, Int) {
        var p = start
        let direct = op == 0x9A || op == 0x9B
        if direct { p += 4 }                                   // (base address)
        guard p + 10 <= d.count else { throw FormatError.notThisFormat("a QuickDraw picture") }
        let rbWord = wordBE(d, p)
        let isPixMap = direct || rbWord & 0x8000 != 0
        let rowBytes = rbWord & 0x3FFF
        let bounds = rect(d, p + 2)
        p += 10
        var pixelSize = 1, packType = 0, cmpCount = 1
        var table = [Int: (UInt8, UInt8, UInt8)]()
        if isPixMap {
            packType = wordBE(d, p + 2)
            pixelSize = wordBE(d, p + 18)
            cmpCount = wordBE(d, p + 20)
            p += 36
            if !direct {
                let flags = wordBE(d, p + 4), size = wordBE(d, p + 6) + 1
                p += 8
                for k in 0..<size {
                    let v = flags & 0x8000 != 0 ? k : wordBE(d, p)
                    table[v] = (to8(wordBE(d, p + 2)), to8(wordBE(d, p + 4)), to8(wordBE(d, p + 6)))
                    p += 8
                }
            }
        }
        let src = rect(d, p), dst = rect(d, p + 8)
        p += 18                                                // (and the transfer mode)
        if op == 0x91 || op == 0x99 || op == 0x9B { p += wordBE(d, p) }
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0, w <= 4096, h <= 4096 else { throw FormatError.notThisFormat("a QuickDraw picture") }
        var rgb = [UInt8](repeating: 255, count: w * h * 3)
        let packed = op != 0x90 && op != 0x91 && rowBytes >= 8
        if direct && pixelSize == 32 && packType == 0 { packType = 4 }
        if direct && pixelSize == 16 && packType == 0 { packType = 3 }
        for y in 0..<h {
            var row: [UInt8]
            if direct && (packType == 1 || rowBytes < 8) || !packed && !direct {
                row = Array(d[p..<min(d.count, p + rowBytes)]); p += rowBytes
            } else if direct && packType == 2 {
                row = Array(d[p..<min(d.count, p + w * 3)]); p += w * 3
            } else {
                let count = rowBytes > 250 ? wordBE(d, p) : Int(d[p])
                p += rowBytes > 250 ? 2 : 1
                row = unpackBits(d, p, count, unit: direct && pixelSize == 16 ? 2 : 1)
                p += count
            }
            row += [UInt8](repeating: 0, count: max(0, rowBytes + 4 * w - row.count))
            for x in 0..<w {
                let c: (UInt8, UInt8, UInt8)
                if !direct {
                    let bit = x * pixelSize
                    let v = Int(row[bit >> 3] >> UInt8(8 - pixelSize - (bit & 7))) & ((1 << pixelSize) - 1)
                    c = isPixMap ? (table[v] ?? (0, 0, 0)) : (v != 0 ? (0, 0, 0) : (255, 255, 255))
                } else if pixelSize == 16 {
                    let v = Int(row[x * 2]) << 8 | Int(row[x * 2 + 1])
                    c = (TGAFormat.five(v >> 10 & 31), TGAFormat.five(v >> 5 & 31), TGAFormat.five(v & 31))
                } else if packType == 1 || rowBytes < 8 {
                    c = (row[x * 4 + 1], row[x * 4 + 2], row[x * 4 + 3])
                } else if packType == 2 {
                    c = (row[x * 3], row[x * 3 + 1], row[x * 3 + 2])
                } else {
                    let skipAlpha = cmpCount == 4 ? w : 0
                    c = (row[skipAlpha + x], row[skipAlpha + w + x], row[skipAlpha + 2 * w + x])
                }
                let o = (y * w + x) * 3
                rgb[o] = c.0; rgb[o + 1] = c.1; rgb[o + 2] = c.2
            }
        }
        return (rgb, src, dst, bounds, p)
    }
}
