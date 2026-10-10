import XCTest
@testable import SCCore

final class PlatformTests: XCTestCase {
    /// A low resolution Degas file with a recognisable pattern.
    private func degas() -> [UInt8] {
        var d: [UInt8] = [0, 0]
        for c in 0..<16 { d += [UInt8(c & 7), UInt8((c & 7) << 4 | (c & 7))] }
        for i in 0..<32000 { d.append(UInt8((i * 7 + i / 160) & 0xFF)) }
        return d
    }

    /// PackBits using literal records only.
    private func literals(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let n = min(128, bytes.count - i)
            out.append(UInt8(n - 1))
            out += bytes[i..<(i + n)]
            i += n
        }
        return out
    }

    func testDegasPixelOrder() throws {
        var d = [UInt8](repeating: 0, count: 32034)
        d[34] = 0x80          // plane 0, pixel 0
        d[36] = 0x40          // plane 1, pixel 1
        d[40] = 0x20          // plane 3, pixel 2
        d[4] = 0x07           // colour 1 = red
        let s = try AtariFormats.loadDegas(d)
        XCTAssertEqual(Array(s.pixels[0..<4]), [1, 2, 8, 0])
        XCTAssertEqual(s.palettes[0][1], 0xF00)
    }

    func testDegasEliteMatchesDegas() throws {
        let plain = degas()
        var packed = Array(plain[0..<34])
        packed[0] = 0x80
        var planar: [UInt8] = []
        for y in 0..<200 {
            for plane in 0..<4 {
                for i in 0..<40 { planar.append(plain[34 + y * 160 + (i / 2) * 8 + plane * 2 + (i & 1)]) }
            }
        }
        packed += literals(planar)
        XCTAssertEqual(try AtariFormats.loadDegasElite(packed).pixels, try AtariFormats.loadDegas(plain).pixels)
    }

    func testNeochromeMatchesDegas() throws {
        let plain = degas()
        var neo = [UInt8](repeating: 0, count: 128)
        neo.replaceSubrange(4..<36, with: plain[2..<34])
        neo += plain[34...]
        let a = try AtariFormats.loadNeochrome(neo), b = try AtariFormats.loadDegas(plain)
        XCTAssertEqual(a.pixels, b.pixels)
        XCTAssertEqual(a.palettes, b.palettes)
    }

    func testTinyMatchesDegas() throws {
        let plain = degas()
        var words: [UInt8] = []
        for plane in 0..<4 {
            for column in 0..<20 {
                for row in 0..<200 {
                    let at = 34 + row * 160 + column * 8 + plane * 2
                    words += [plain[at], plain[at + 1]]
                }
            }
        }
        // One control record: "1, count" = that many literal words.
        var tiny: [UInt8] = [0] + plain[2..<34]
        tiny += [0, 3, 0x3E, 0x80]              // 3 control bytes, 16000 data words
        tiny += [1, 0x3E, 0x80]
        tiny += words
        XCTAssertEqual(try AtariFormats.loadTiny(tiny).pixels, try AtariFormats.loadDegas(plain).pixels)
    }

    func testSpectrumPaletteSwitching() throws {
        // Every pixel is colour 1; the three palettes of each line make it red, green, blue.
        var spu = [UInt8](repeating: 0, count: 51104)
        for y in 1..<200 { for x in 0..<20 { spu[y * 160 + x * 8] = 0xFF; spu[y * 160 + x * 8 + 1] = 0xFF } }
        for line in 0..<199 {
            let at = 32000 + line * 96
            spu[at + 2] = 0x07                   // palette 0, colour 1: red
            spu[at + 32 + 3] = 0x70              // palette 1, colour 1: green
            spu[at + 64 + 3] = 0x07              // palette 2, colour 1: blue
        }
        let image = try AtariFormats.loadSpectrum(spu)
        XCTAssertTrue(image.pixel(0, 0) == (0, 0, 0))            // top line is always black
        XCTAssertTrue(image.pixel(4, 10) == (255, 0, 0))         // before x = 5
        XCTAssertTrue(image.pixel(5, 10) == (0, 255, 0))         // 5 ..< 165
        XCTAssertTrue(image.pixel(165, 10) == (0, 0, 255))

        // The same picture, packed.
        var spc: [UInt8] = [0x53, 0x50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var bitmap: [UInt8] = []
        var left = 7960
        while left > 0 { let n = min(129, left); bitmap += [UInt8(bitPattern: Int8(2 - n)), 0xFF]; left -= n }
        left = 7960 * 3
        while left > 0 { let n = min(129, left); bitmap += [UInt8(bitPattern: Int8(2 - n)), 0x00]; left -= n }
        spc[6] = UInt8(bitmap.count >> 8)
        spc[7] = UInt8(bitmap.count & 0xFF)
        spc += bitmap
        for _ in 0..<199 { spc += [0, 2, 0x07, 0x00, 0, 2, 0x00, 0x70, 0, 2, 0x00, 0x07] }
        XCTAssertEqual(try AtariFormats.loadSpectrumCompressed(spc).rgb, image.rgb)
    }

    func testHoldAndModify() throws {
        func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
            Array(name.utf8) + [0, 0, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body + (body.count & 1 == 1 ? [0] : [])
        }
        // 16 x 1, six planes, HAM. Pixel 0: palette colour 1. Pixel 1: set blue to 15. Pixel 2: set red to 15.
        let header: [UInt8] = [0, 16, 0, 1, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 10, 11, 0, 16, 0, 1]
        var cmap = [UInt8](repeating: 0, count: 48)
        cmap[4] = 0xF0                                   // colour 1 = green
        let values = [0b000001, 0b011111, 0b101111]
        var body: [UInt8] = []
        for plane in 0..<6 {
            var byte: UInt8 = 0
            for (x, v) in values.enumerated() where v & (1 << plane) != 0 { byte |= 0x80 >> UInt8(x) }
            body += [byte, 0]
        }
        let inner = Array("ILBM".utf8) + chunk("BMHD", header) + chunk("CMAP", cmap)
            + chunk("CAMG", [0, 0, 0x08, 0]) + chunk("BODY", body)
        let file = Array("FORM".utf8) + [0, 0, UInt8(inner.count >> 8), UInt8(inner.count & 0xFF)] + inner
        let image = try AmigaFormats.loadIFF(file)
        XCTAssertTrue(image.pixel(0, 0) == (0, 255, 0))
        XCTAssertTrue(image.pixel(1, 0) == (0, 255, 255))
        XCTAssertTrue(image.pixel(2, 0) == (255, 255, 255))
    }

    func testC64Formats() throws {
        var doodle = [UInt8](repeating: 0, count: 9026)
        doodle[2] = 0x26                // cell 0: ink red (2), paper blue (6)
        doodle[1026] = 0x80
        let d = try C64Formats.loadDoodle(doodle)
        XCTAssertEqual(Array(d.pixels[0..<2]), [2, 6])

        var koala = [UInt8](repeating: 0, count: 10003)
        koala[2] = 0b00011011           // background, screen high, screen low, colour memory
        koala[8002] = 0x25
        koala[9002] = 0x07
        koala[10002] = 0x0E
        let k = try C64Formats.loadKoala(koala)
        XCTAssertEqual(Array(k.pixels[0..<8]), [14, 14, 2, 2, 5, 5, 7, 7])
        XCTAssertEqual(k.palettes[0], C64Formats.palette)

        var shop = [UInt8](repeating: 0, count: 8002)
        shop[2] = 0x40
        XCTAssertEqual(Array(try C64Formats.loadPrintShop(shop).pixels[0..<3]), [0, 1, 0])
    }

    func testMacPaintAndScreenMaker() throws {
        // MacBinary wrapper, 512-byte header, then 720 rows: the first all ink, the rest blank.
        var file = [UInt8](repeating: 0, count: 128 + 512)
        file[1] = 4
        file[86] = 0x10                 // data fork length, non-zero
        file += [UInt8(bitPattern: -71), 0xFF]
        for _ in 1..<720 { file += [UInt8(bitPattern: -71), 0x00] }
        let narrow = try MacFormats.loadMacPaint320(file)
        XCTAssertEqual(narrow.height, 720)
        XCTAssertEqual(narrow.pixels[0], 0)
        XCTAssertEqual(narrow.pixels[576], 15)
        let grey = try MacFormats.loadMacPaint640(file)
        XCTAssertEqual(grey.height, 360)
        XCTAssertTrue([1, 2].contains(grey.pixels[0]))      // one inked line of the pair: mid grey
        XCTAssertEqual(grey.pixels[576], 3)

        var screen = [UInt8](repeating: 0, count: 21888)
        screen[0] = 0x80
        let s = try MacFormats.loadScreenMaker(screen)
        XCTAssertEqual(Array(s.pixels[0..<2]), [0, 1])
    }
}
