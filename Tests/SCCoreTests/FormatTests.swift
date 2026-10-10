import XCTest
@testable import SCCore

final class FormatTests: XCTestCase {
    /// Minimal LZW packer matching the decoder: emits a clear code, then codes.
    private func lzwPack(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var acc = 0, bits = 0, width = 9, top = 0x200, next = 0x102
        var table: [[UInt8]: Int] = [:]
        func emit(_ code: Int) {
            acc |= code << bits
            bits += width
            while bits >= 8 {
                out.append(UInt8(acc & 0xFF))
                acc >>= 8
                bits -= 8
            }
        }
        emit(0x100)
        var current: [UInt8] = []
        var first = true
        for byte in data {
            let longer = current + [byte]
            if longer.count == 1 || table[longer] != nil {
                current = longer
                continue
            }
            emit(current.count == 1 ? Int(current[0]) : table[current]!)
            if !first, next < 4096 {
                // The decoder adds an entry for every code after the first.
            }
            first = false
            if next < 4096 {
                table[longer] = next
                next += 1
                if next > top && width < 12 {
                    width += 1
                    top <<= 1
                }
            }
            current = [byte]
        }
        if !current.isEmpty { emit(current.count == 1 ? Int(current[0]) : table[current]!) }
        emit(0x101)
        if bits > 0 { out.append(UInt8(acc & 0xFF)) }
        return out
    }

    func testLZWRoundTrip() {
        var data: [UInt8] = []
        for i in 0..<20000 { data.append(UInt8((i / 37 + (i % 5) * 3) & 0xFF)) }
        data += [UInt8](repeating: 9, count: 3000)
        XCTAssertEqual(LZW.decode(lzwPack(data), limit: data.count), data)
    }

    func testDreamGrafixScreen() throws {
        var screen = ScreenImage(width: 320, height: 200, is640: false)
        for i in 0..<screen.pixels.count { screen.pixels[i] = UInt8((i / 9 + i / 320) & 15) }
        let loaded = try IIgsFormats.loadDreamGrafix(lzwPack(SHRFormats.saveScreen(screen)))
        XCTAssertEqual(loaded.pixels, screen.pixels)
        XCTAssertEqual(loaded.palettes[0], ScreenImage.standard320)
    }

    func testRunUnpacker() throws {
        // byte run, word run, 3-byte run, literal, long-count byte run
        let packed: [UInt8] = [0x02, 7, 0x41, 1, 2, 0x60, 9, 8, 7, 0xC2, 5, 6, 0x20, 0x04, 3]
        let expect: [UInt8] = [7, 7, 7, 1, 2, 1, 2, 9, 8, 7, 5, 6] + [UInt8](repeating: 3, count: 5)
        XCTAssertEqual(try IIgsFormats.unpackRuns(packed, count: expect.count), expect)
    }

    func test3200Compressed() throws {
        // Colour tables: every line's table is $0FFF repeated; pixels all zero.
        var file: [UInt8] = [0, 0, 0, 0, 0, 0, 0]
        var tables: [UInt8] = []
        for _ in 0..<(6400 / 64) { tables += [0x5F, 0xFF, 0x0F] }   // word run, 32 words each
        file[5] = UInt8(tables.count & 0xFF)
        file[6] = UInt8(tables.count >> 8)
        var pixels: [UInt8] = []
        for _ in 0..<3 { pixels += [0x3F, 0xFF, 0x00] }             // 3 x 8192 zero bytes
        pixels += [0x3D, 0x3F, 0x00]                                // 7424 more
        let image = try IIgsFormats.load3200Compressed(file + tables + pixels)
        XCTAssertEqual(image.width, 320)
        XCTAssertTrue(image.rgb.allSatisfy { $0 == 255 })
    }

    func testPrintShop() throws {
        var mono = [UInt8](repeating: 0, count: 572)
        mono[0] = 0x80
        let bw = try IIgsFormats.loadPrintShop(mono)
        XCTAssertEqual(bw.pixels[0], 0)      // ink
        XCTAssertEqual(bw.pixels[1], 15)     // paper
        var colour = [UInt8](repeating: 0, count: 1716)
        colour[0] = 0xC0                     // yellow plane: pixels 0 and 1
        colour[572] = 0x40                   // magenta plane: pixel 1
        colour[1144] = 0x20                  // cyan plane: pixel 2
        let c = try IIgsFormats.loadPrintShopGS(colour)
        XCTAssertEqual(Array(c.pixels[0..<4]), [9, 6, 4, 15])   // yellow, orange, blue, white
    }

    func testIconFile() throws {
        var file = [UInt8](repeating: 0, count: 26)
        file[4] = 1
        var record = [UInt8](repeating: 0, count: 86)
        record[66] = 4
        record.replaceSubrange(67..<71, with: Array("TEST".utf8))
        func icon(_ w: Int, _ h: Int, fill: UInt8) -> [UInt8] {
            var out: [UInt8] = []
            let rowBytes = (w + 1) / 2
            putWord(&out, 0x8000); putWord(&out, rowBytes * h); putWord(&out, h); putWord(&out, w)
            out += [UInt8](repeating: fill, count: rowBytes * h)
            out += [UInt8](repeating: 0xFF, count: rowBytes * h)
            return out
        }
        record += icon(8, 4, fill: 0x1B) + icon(4, 2, fill: 0x00)
        record[0] = UInt8(record.count & 0xFF)
        record[1] = UInt8(record.count >> 8)
        file += record + [0, 0]
        guard case .choice(let titles, let pick) = try IIgsFormats.loadIconFile(file) else { return XCTFail() }
        XCTAssertEqual(titles, ["TEST (large)", "TEST (small)"])
        guard case .screen(let screen) = try pick(0) else { return XCTFail() }
        XCTAssertEqual(screen.width, 32)
        XCTAssertEqual(screen.height, 12)
        let row = 4 * 32 + 8
        XCTAssertEqual(Array(screen.pixels[row..<(row + 4)]), [0, 1, 2, 3])   // nibbles 1, B
        XCTAssertEqual(screen.pixels[0], 3)
    }

    func testDigitizers() throws {
        var ast = [UInt8](repeating: 0, count: 96000)
        ast[0] = 0xF0                // red, pixel 0
        ast[32000] = 0x0F            // green, pixel 1
        let a = try IIgsFormats.loadAST(ast)
        XCTAssertTrue(a.pixel(0, 0) == (255, 0, 0))
        XCTAssertTrue(a.pixel(1, 0) == (0, 255, 0))

        var eyes = [UInt8](repeating: 0, count: 192000)
        eyes[128000 + 3 * 200 + 5] = 0x3F     // blue plane, column 3, row 5
        let e = try IIgsFormats.loadComputerEyes(eyes)
        XCTAssertTrue(e.pixel(3, 5) == (0, 0, 255))

        var scan = [UInt8](repeating: 0, count: 256 + 8)
        scan[0x0F] = 4               // width 4 pixels
        scan[0x1E] = 3               // 4 rows
        scan[256] = 0xF8
        let t = try AppleIIFormats.loadThunderScan(scan)
        XCTAssertEqual(t.height, 4)
        XCTAssertTrue(t.pixel(0, 0) == (255, 255, 255))
        XCTAssertTrue(t.pixel(1, 0) == (136, 136, 136))
    }

    func testDoubleHiResColourOrder() throws {
        // Magenta (colour 1) fills the screen as aux $08, main $11, aux $22, main $44.
        var file = [UInt8](repeating: 0, count: 16384)
        for i in 0..<8192 {
            file[i] = i % 2 == 0 ? 0x08 : 0x22
            file[8192 + i] = i % 2 == 0 ? 0x11 : 0x44
        }
        // Row 0 starts at offset 0, so its columns alternate from an even byte.
        let screen = try AppleIIFormats.loadDoubleHiRes(file, colour: true)
        XCTAssertTrue(screen.pixels[0..<280].allSatisfy { $0 == 1 })
        XCTAssertEqual(screen.palettes[0][1], 0xD03)
    }

    func test3201File() throws {
        var file: [UInt8] = [0xC1, 0xD0, 0xD0, 0x00]
        for _ in 0..<200 { for c in 0..<16 { file += [UInt8(c * 0x11), UInt8(c)] } }   // greys, 000…FFF
        file += PackBytes.pack([UInt8](repeating: 0xF0, count: 32000))
        let image = try IIgsFormats.load3200Compressed(file)
        // Tables are stored last colour first: pixel value 15 is entry 0 (black), 0 is entry 15 (white).
        XCTAssertTrue(image.pixel(0, 0) == (0, 0, 0))
        XCTAssertTrue(image.pixel(1, 0) == (255, 255, 255))
    }

    func testPaintworksGoldForces640() throws {
        var screen = ScreenImage(width: 320, height: 10, is640: false)
        for i in 0..<screen.pixels.count { screen.pixels[i] = UInt8(i & 15) }
        let fixed = try IIgsFormats.loadPaintworksGold(SHRFormats.saveApplePreferred(screen))
        XCTAssertTrue(fixed.is640)
        XCTAssertEqual(fixed.width, 640)
        XCTAssertTrue(fixed.scbs.allSatisfy { $0 == 0x80 })
        XCTAssertEqual(fixed.packedRow(0), screen.packedRow(0))
    }

    func testTextScreen() throws {
        // A stand-in character set: every glyph is a solid block.
        AppleIIFormats.textGlyphs = [[UInt8]](repeating: [UInt8](repeating: 0x7F, count: 8), count: 95)
        var memory = [UInt8](repeating: 0xA0, count: 1024)    // normal spaces…
        AppleIIFormats.textGlyphs![0] = [UInt8](repeating: 0, count: 8)
        memory[0] = 0xC1                                      // normal "A" at row 0, column 0
        memory[0x80 + 1] = 0x20                               // inverse space at row 1, column 1
        let screen = try AppleIIFormats.loadTextScreen(memory, columns: 40)
        XCTAssertEqual(screen.width, 280)
        XCTAssertEqual(screen.pixels[0], 15)
        XCTAssertEqual(screen.pixels[7], 0)
        XCTAssertEqual(screen.pixels[8 * 280 + 7], 15)
    }
}
