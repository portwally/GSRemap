import Foundation

public enum FormatError: Error, CustomStringConvertible {
    case notThisFormat(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .notThisFormat(let s): return "This file doesn't look like \(s)."
        case .unsupported(let s): return s
        }
    }
}

@inline(__always) func word(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
@inline(__always) func long(_ d: [UInt8], _ i: Int) -> Int { word(d, i) | word(d, i + 2) << 16 }
func putWord(_ out: inout [UInt8], _ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8 & 0xFF)) }
func putLong(_ out: inout [UInt8], _ v: Int) { putWord(&out, v & 0xFFFF); putWord(&out, v >> 16 & 0xFFFF) }

/// Apple IIgs Super Hi-Res file formats: types $C0 (PNT) and $C1 (PIC).
public enum SHRFormats {
    static func table(_ d: [UInt8], _ at: Int) -> [Color12] {
        (0..<16).map { Color12(word(d, at + $0 * 2) & 0x0FFF) }
    }

    // MARK: $C1/0000 — uncompressed screen

    public static func loadScreen(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 32000 else { throw FormatError.notThisFormat("an uncompressed SHR screen") }
        let scbs: [UInt8] = d.count >= 32200 ? Array(d[32000..<32200]) : [UInt8](repeating: 0, count: 200)
        let is640 = scbs.filter { $0 & 0x80 != 0 }.count > 100
        var palettes: [[Color12]] = []
        if d.count >= 32768 {
            palettes = (0..<16).map { table(d, 32256 + $0 * 32) }
        } else {
            palettes = [is640 ? ScreenImage.standard640 : ScreenImage.standard320]
        }
        var screen = ScreenImage(width: is640 ? 640 : 320, height: 200, is640: is640, palettes: palettes)
        screen.scbs = scbs.map { is640 ? $0 | 0x80 : $0 & 0x7F }
        for y in 0..<200 { screen.setPackedRow(y, Array(d[(y * 160)..<(y * 160 + 160)])) }
        return screen
    }

    /// A 32768-byte screen dump. Images that aren't exactly one screen are cropped or padded.
    public static func saveScreen(_ screen: ScreenImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32768)
        for y in 0..<min(200, screen.height) {
            let row = screen.packedRow(y)
            for x in 0..<min(160, row.count) { out[y * 160 + x] = row[x] }
            out[32000 + y] = screen.scbs[y]
        }
        for p in 0..<min(16, screen.palettes.count) {
            for c in 0..<16 {
                out[32256 + p * 32 + c * 2] = UInt8(screen.palettes[p][c] & 0xFF)
                out[32256 + p * 32 + c * 2 + 1] = UInt8(screen.palettes[p][c] >> 8)
            }
        }
        return out
    }

    // MARK: $C1/0002 — "3200 colour" (Brooks), one palette per line

    public static func load3200(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 38400 else { throw FormatError.notThisFormat("a \"3200 color\" picture") }
        var screen = ScreenImage(width: 320, height: 200, is640: false, palettes: [])
        // Each line's table is stored last colour first.
        screen.palettes = (0..<200).map { Array(table(d, 32000 + $0 * 32).reversed()) }
        for y in 0..<200 { screen.setPackedRow(y, Array(d[(y * 160)..<(y * 160 + 160)])) }
        return screen
    }

    // MARK: $C0/0001 — PackBytes screen

    public static func loadPacked(_ d: [UInt8]) throws -> ScreenImage {
        let raw = PackBytes.unpack(d, limit: 32768)
        guard raw.count >= 32000 else { throw FormatError.notThisFormat("a PackBytes screen") }
        return try loadScreen(raw)
    }

    public static func savePacked(_ screen: ScreenImage) -> [UInt8] {
        PackBytes.pack(saveScreen(screen))
    }

    // MARK: $C0/0000 — PaintWorks

    public static func loadPaintWorks(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count > 0x222 else { throw FormatError.notThisFormat("a PaintWorks picture") }
        let raw = PackBytes.unpack(d, from: 0x222)
        let height = raw.count / 160
        guard height > 0 else { throw FormatError.notThisFormat("a PaintWorks picture") }
        var screen = ScreenImage(width: 320, height: height, is640: false, palettes: [table(d, 0)])
        for y in 0..<height { screen.setPackedRow(y, Array(raw[(y * 160)..<(y * 160 + 160)])) }
        return screen
    }

    public static func savePaintWorks(_ screen: ScreenImage) throws -> [UInt8] {
        guard !screen.is640 else {
            throw FormatError.unsupported("PaintWorks format only holds 320 mode pictures.")
        }
        var out: [UInt8] = []
        for c in screen.palettes[0] { putWord(&out, Int(c)) }
        putWord(&out, 0)
        out.append(contentsOf: [UInt8](repeating: 0, count: 512))
        var raw: [UInt8] = []
        for y in 0..<screen.height {
            var row = screen.packedRow(y)
            row = Array(row.prefix(160)) + [UInt8](repeating: 0, count: max(0, 160 - row.count))
            raw.append(contentsOf: row)
        }
        out.append(contentsOf: PackBytes.pack(raw))
        return out
    }

    // MARK: $C0/0002 — Apple Preferred

    public static func isApplePreferred(_ d: [UInt8]) -> Bool {
        guard d.count > 10 else { return false }
        let n = Int(d[4])
        guard n > 0, n < 16, d.count > 5 + n else { return false }
        return d[5..<(5 + n)].allSatisfy { $0 >= 0x20 && $0 < 0x7F } && long(d, 0) <= d.count + 4
    }

    public static func loadApplePreferred(_ d: [UInt8], force640: Bool = false) throws -> ScreenImage {
        guard isApplePreferred(d) else { throw FormatError.notThisFormat("an Apple Preferred picture") }
        var screen: ScreenImage?
        var multipal: [[Color12]]?
        var at = 0
        while at + 5 < d.count {
            let length = long(d, at)
            guard length > 5, at + length <= d.count else { break }
            let nameLength = Int(d[at + 4])
            let name = String(decoding: d[(at + 5)..<(at + 5 + nameLength)], as: UTF8.self)
            var p = at + 5 + nameLength
            if name == "MAIN" {
                let masterMode = word(d, p)
                let pixelsPerLine = word(d, p + 2)
                let tableCount = word(d, p + 4)
                p += 6
                let tables = (0..<tableCount).map { table(d, p + $0 * 32) }
                p += tableCount * 32
                let lines = word(d, p)
                p += 2
                let is640 = force640 || masterMode & 0x80 != 0
                var s = ScreenImage(width: force640 ? 640 : pixelsPerLine, height: lines, is640: is640,
                                    palettes: tables.isEmpty ? nil : tables)
                var sizes: [Int] = []
                for y in 0..<lines {
                    sizes.append(word(d, p))
                    let mode = UInt8(word(d, p + 2) & 0xFF)
                    s.scbs[y] = force640 ? 0x80 : (is640 ? mode | 0x80 : mode & 0x7F)
                    p += 4
                }
                for y in 0..<lines {
                    guard p + sizes[y] <= d.count else { break }
                    let row = PackBytes.unpack(Array(d[p..<(p + sizes[y])]), limit: s.bytesPerRow)
                    s.setPackedRow(y, row)
                    p += sizes[y]
                }
                screen = s
            } else if name == "MULTIPAL" {
                let n = word(d, p)
                multipal = (0..<n).map { table(d, p + 2 + $0 * 32) }
            }
            at += length
        }
        guard var result = screen else { throw FormatError.notThisFormat("an Apple Preferred picture") }
        if let multipal, multipal.count >= result.height { result.palettes = multipal }
        return result
    }

    public static func saveApplePreferred(_ screen: ScreenImage) -> [UInt8] {
        var body: [UInt8] = []
        putWord(&body, screen.is640 ? 0x80 : 0x00)
        putWord(&body, screen.width)
        let tables = screen.palettes.count > 16 ? [screen.palettes[0]] : screen.palettes
        putWord(&body, tables.count)
        for t in tables { for c in t { putWord(&body, Int(c)) } }
        putWord(&body, screen.height)
        let rows = (0..<screen.height).map { PackBytes.pack(screen.packedRow($0)) }
        for y in 0..<screen.height {
            putWord(&body, rows[y].count)
            putWord(&body, Int(screen.scbs[y]))
        }
        for r in rows { body.append(contentsOf: r) }

        func block(_ name: String, _ body: [UInt8]) -> [UInt8] {
            var out: [UInt8] = []
            putLong(&out, 4 + 1 + name.utf8.count + body.count)
            out.append(UInt8(name.utf8.count))
            out.append(contentsOf: Array(name.utf8))
            out.append(contentsOf: body)
            return out
        }
        var out = block("MAIN", body)
        if screen.palettes.count > 16 {
            var mp: [UInt8] = []
            putWord(&mp, screen.palettes.count)
            for t in screen.palettes { for c in t { putWord(&mp, Int(c)) } }
            out.append(contentsOf: block("MULTIPAL", mp))
        }
        return out
    }

    // MARK: Auto-detect

    /// "SuperHiRes ($C0/PNT, $C1/PIC)": works out which of the SHR variants a file is.
    public static func loadAny(_ d: [UInt8]) throws -> ScreenImage {
        if d.count == 32768 || d.count == 32000 { return try loadScreen(d) }
        if d.count == 38400 { return try load3200(d) }
        if isApplePreferred(d) { return try loadApplePreferred(d) }
        if let packed = try? loadPacked(d) { return packed }
        return try loadPaintWorks(d)
    }
}
