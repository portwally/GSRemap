import Foundation

// Apple II pictures MegaconvertGS reads beyond SuperConvert (its src/Apple.s, Formats.s
// PairDHR, WOA.s): packed screens, fadden's LZ4FH, Double HiRes in two files and bmp2dhr's
// picture pieces; and Springboard Publisher's Works of Art pages.

extension AppleIIFormats {
    /// fadden's LZ4FH (fhpack; ProDOS type $08, aux type $8066): magic $66, then sequences of
    /// a token (literal bytes in the high 4 bits, 15: plus the next byte; match length - 4 in
    /// the low 4, 15: plus the next byte, which is 253 for no match and 254 for the end), the
    /// literals, and a match's place counted from the screen's start (2 bytes, low first).
    public static func unpackLZ4FH(_ d: [UInt8]) -> [UInt8]? {
        guard d.count >= 2, d[0] == 0x66 else { return nil }
        var o = [UInt8](repeating: 0, count: 8192)
        var ip = 1, op = 0
        func next() -> Int? { guard ip < d.count else { return nil }; ip += 1; return Int(d[ip - 1]) }
        while true {
            guard let token = next() else { return nil }
            var lit = token >> 4
            if lit == 15 { guard let x = next() else { return nil }; lit += x }
            guard ip + lit <= d.count, op + lit <= 8192 else { return nil }
            o.replaceSubrange(op..<(op + lit), with: d[ip..<(ip + lit)]); ip += lit; op += lit
            var m = token & 15
            if m == 15 {
                guard let x = next() else { return nil }
                if x == 253 { continue }
                if x == 254 { return o }
                m += x
            }
            m += 4
            guard let lo = next(), let hi = next() else { return nil }
            var from = lo | hi << 8
            guard from + m <= 8192, op + m <= 8192 else { return nil }
            for _ in 0..<m { o[op] = o[from]; op += 1; from += 1 }
        }
    }

    /// A HiRes or Double HiRes screen of `size` bytes from a file: as it is, or packed with
    /// fadden's LZ4FH (HiRes) or with PackBytes (ProDOS type $08, aux type $4000 or $4001).
    static func unpacked(_ d: [UInt8], size: Int) -> [UInt8] {
        if (size - 8...size).contains(d.count) { return d }
        if size == 8192, let lz = unpackLZ4FH(d) { return lz }
        let p = PackBytes.unpack(d, limit: size)
        return p.count >= size - 8 ? p : d
    }

    /// bmp2dhr's Double HiRes picture piece (Bill Buckels' DHR format): "DHR" (or "DHM", a
    /// black & white mask), the bytes a row (both halves, 4 for 7 dots: 4-80), the rows
    /// (1-192), then each row's auxiliary half and main half. Placed at the top left of a
    /// black screen; the size it covers (bytes, rows), or nil.
    public static func dhrPiece(_ d: [UInt8]) -> (screen: [UInt8], bytes: Int, rows: Int, mask: Bool)? {
        guard d.count >= 9, d[0] == 0x44, d[1] == 0x48, d[2] == 0x52 || d[2] == 0x4D else { return nil }
        let w = Int(d[3]), h = Int(d[4])
        guard w >= 4, w <= 80, w % 4 == 0, h >= 1, h <= 192, d.count >= 5 + w * h else { return nil }
        var s = [UInt8](repeating: 0, count: 16384)
        var at = 5
        for y in 0..<h {
            let row = rowOffset(y)
            for k in 0..<(w / 2) { s[row + k] = d[at + k] }
            for k in 0..<(w / 2) { s[8192 + row + k] = d[at + w / 2 + k] }
            at += w
        }
        return (s, w, h, d[2] == 0x4D)
    }

    /// Double HiRes from a file: a piece (cropped to its size), a packed screen, or NAME.BIN
    /// (main memory) with NAME.AUX (auxiliary) beside it, 8184 or 8192 bytes each (Beagle
    /// Graphics, bmp2dhr's option A), opened either way.
    public static func loadDoubleHiRes(url: URL, colour: Bool) throws -> ScreenImage {
        let d = [UInt8](try Data(contentsOf: url))
        if let piece = dhrPiece(d) {
            var s = try loadDoubleHiRes(piece.screen, colour: colour)
            let width = piece.bytes * 7 / (colour ? 2 : 1)
            s = s.cropped(width: width, height: piece.rows)
            return s
        }
        if (8184...8192).contains(d.count), let other = pairHalf(url) {
            let aux = url.pathExtension.uppercased() == "AUX" ? d : other
            let main = url.pathExtension.uppercased() == "AUX" ? other : d
            var s = [UInt8](repeating: 0, count: 16384)
            s.replaceSubrange(0..<aux.count, with: aux)
            s.replaceSubrange(8192..<(8192 + main.count), with: main)
            return try loadDoubleHiRes(s, colour: colour)
        }
        return try loadDoubleHiRes(unpacked(d, size: 16384), colour: colour)
    }

    /// The other half of a NAME.BIN / NAME.AUX pair, if it is there (8184-8192 bytes).
    static func pairHalf(_ url: URL) -> [UInt8]? {
        let ext = url.pathExtension
        let wanted: String
        switch ext.uppercased() { case "BIN": wanted = "AUX"; case "AUX": wanted = "BIN"; default: return nil }
        let name = ext == ext.lowercased() ? wanted.lowercased() : wanted
        let other = url.deletingPathExtension().appendingPathExtension(name)
        guard let data = try? Data(contentsOf: other), (8184...8192).contains(data.count) else { return nil }
        return [UInt8](data)
    }

    /// HiRes from a file: as it is, or packed (PackBytes or LZ4FH).
    public static func loadHiRes(packed d: [UInt8], mono: Bool) throws -> ScreenImage {
        let s = unpacked(d, size: 8192)
        return mono ? try loadHiResMono(s) : try loadHiRes(s)
    }
}

extension ScreenImage {
    /// The top left w x h of the picture.
    public func cropped(width w: Int, height h: Int) -> ScreenImage {
        var s = ScreenImage(width: w, height: h, is640: is640, palettes: palettes)
        for y in 0..<h {
            s.scbs[y] = scbs[y]
            for x in 0..<w { s.pixels[y * w + x] = pixels[y * width + x] }
        }
        return s
    }
}

// MARK: - Works of Art (Springboard Publisher)

public enum WorksOfArt {
    /// A Works of Art file: a 16-byte header ("SS" at 5, entries at $0B, data block at $0D),
    /// a directory of 16-byte entries (type, ID, length at +8), the chunks one after another
    /// from block B. Chunk (0, 4) lists the pages' names; chunk (n, $0B) is page n.
    public static func load(_ d: [UInt8]) throws -> LoadedImage {
        guard d.count >= 16, d[5] == 0x53, d[6] == 0x53 else { throw FormatError.notThisFormat("a Works of Art file") }
        let n = word(d, 0x0B), base = Int(d[0x0D]) * 512
        guard d.count >= 16 + n * 16 else { throw FormatError.notThisFormat("a Works of Art file") }
        var chunks: [(type: Int, id: Int, at: Int, length: Int)] = []
        var at = base
        for k in 0..<n {
            let e = 16 + k * 16
            let length = word(d, e + 8)
            chunks.append((word(d, e), word(d, e + 2), at, length))
            at += length
        }
        func chunk(_ type: Int, _ id: Int) throws -> ArraySlice<UInt8> {
            guard let c = chunks.last(where: { $0.type == type && $0.id == id }), c.at + c.length <= d.count else {
                throw FormatError.unsupported("Cannot handle this variation on the selected type.")
            }
            return d[c.at..<(c.at + c.length)]
        }
        let list = Array(try chunk(0, 4))
        guard list.count >= 3 else { throw FormatError.unsupported("Cannot handle this variation on the selected type.") }
        var names: [String] = [], p = 3
        for _ in 0..<word(list, 0) where p < list.count {
            let len = Int(list[p])
            names.append(String(decoding: list[(p + 1)..<min(list.count, p + 1 + len)], as: UTF8.self))
            p += 1 + len
        }
        return .choice(titles: names) { k in .monochrome(try page(Array(try chunk(k + 1, 0x0B)))) }
    }

    /// A page: a 10-byte header (0, 0, 269, 359 at +2), then codes: a byte below $80 is one cell
    /// of 7 pixels; else a run: L = ((c >> 4) & 7) + 1 pattern bytes, count c & 15 (8 or more:
    /// ((c & 7) << 8) + the next byte), the pattern given count + 1 times. Cells fill strips 7
    /// pixels wide down, up, down ...; bit 0 is the leftmost pixel; a set bit is white.
    static func page(_ c: [UInt8]) throws -> MonoImage {
        guard c.count >= 10, word(c, 2) == 0, word(c, 4) == 0, word(c, 6) == 269, word(c, 8) == 359 else {
            throw FormatError.unsupported("Cannot handle this variation on the selected type.")
        }
        var mono = MonoImage(width: 270, height: 360, white: false)
        var strip = 0, y = 0, down = true
        func put(_ v: UInt8) {
            guard strip < 39 else { return }
            for b in 0..<7 where v & (1 << UInt8(b)) != 0 {
                let x = 7 * strip + b
                if x < 270 { mono.pixels[y * 270 + x] = 1 }
            }
            if down { if y == 359 { strip += 1; down = false } else { y += 1 } }
            else { if y == 0 { strip += 1; down = true } else { y -= 1 } }
        }
        var i = 10
        while i < c.count {
            let b = c[i]; i += 1
            if b < 0x80 { put(b); continue }
            let l = Int((b >> 4) & 7) + 1
            var count = Int(b & 15)
            if count >= 8 {
                guard i < c.count else { throw FormatError.unsupported("Unexpected end of file.") }
                count = (count & 7) << 8 | Int(c[i]); i += 1
            }
            guard i + l <= c.count else { throw FormatError.unsupported("Unexpected end of file.") }
            let pattern = c[i..<(i + l)]; i += l
            for _ in 0...count { for v in pattern { put(v & 0x7F) } }
        }
        return mono
    }
}

extension ScreenImage {
    /// The part between `left`/`top` (inclusive) and `right`/`bottom` (exclusive), clamped to the image.
    /// Each line keeps its control byte; a 3200-colour picture keeps the tables of the lines that stay.
    public func cropped(left: Int, top: Int, right: Int, bottom: Int) -> ScreenImage {
        let l = max(0, min(left, width)), r = max(l, min(right, width))
        let t = max(0, min(top, height)), b = max(t, min(bottom, height))
        let tables = palettes.count > 16 ? Array(palettes[min(t, palettes.count - 1)..<min(max(b, t + 1), palettes.count)]) : palettes
        var s = ScreenImage(width: r - l, height: b - t, is640: is640, palettes: tables.isEmpty ? palettes : tables)
        for y in t..<b {
            s.scbs[y - t] = scbs[y]
            for x in l..<r { s.pixels[(y - t) * (r - l) + (x - l)] = pixels[y * width + x] }
        }
        return s
    }
}
