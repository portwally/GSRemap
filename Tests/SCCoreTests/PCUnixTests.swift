import XCTest
@testable import SCCore

final class PCUnixTests: XCTestCase {
    func testPCXEightBitWithPalette() throws {
        var d = [UInt8](repeating: 0, count: 128)
        d[0] = 10; d[1] = 5; d[2] = 1; d[3] = 8
        d[8] = 3                          // xmax = 3 → 4 pixels wide
        d[65] = 1; d[66] = 4
        d += [0xC3, 7, 9]                 // three 7s, then a 9
        var palette = [UInt8](repeating: 0, count: 768)
        palette[21] = 255                 // colour 7 = red
        palette[29] = 255                 // colour 9 = blue
        d += [12] + palette
        let image = try PCFormats.loadPCX(d)
        XCTAssertEqual(image.width, 4)
        XCTAssertTrue(image.pixel(2, 0) == (255, 0, 0))
        XCTAssertTrue(image.pixel(3, 0) == (0, 0, 255))
    }

    func testPCXOneBitUsesHeaderColours() throws {
        var d = [UInt8](repeating: 0, count: 128)
        d[0] = 10; d[1] = 5; d[2] = 1; d[3] = 1
        d[8] = 7
        d[19] = 255; d[20] = 255; d[21] = 255      // colour 1 = white
        d[65] = 1; d[66] = 2
        d += [0x80, 0x00]
        let image = try PCFormats.loadPCX(d)
        XCTAssertTrue(image.pixel(0, 0) == (255, 255, 255))
        XCTAssertTrue(image.pixel(1, 0) == (0, 0, 0))
    }

    func testGEMImage() throws {
        // 16 x 3, one plane: a solid run, a literal, and a line repeated twice.
        var d: [UInt8] = [0, 1, 0, 8, 0, 1, 0, 2, 0, 85, 0, 85, 0, 16, 0, 3]
        d += [0x82]                               // 2 bytes of ink
        d += [0, 0, 0xFF, 2, 0x80, 2, 0xF0, 0x00] // next line twice: literal F0 00
        let image = try PCFormats.loadGEM(d)
        XCTAssertEqual(image.height, 3)
        XCTAssertTrue(image.pixel(15, 0) == (0, 0, 0))
        XCTAssertTrue(image.pixel(3, 1) == (0, 0, 0))
        XCTAssertTrue(image.pixel(4, 1) == (255, 255, 255))
        XCTAssertTrue(image.pixel(3, 2) == (0, 0, 0))
    }

    func testFliAwayFrame() throws {
        var d = [UInt8](repeating: 0, count: 512)
        d[2] = 0x00; d[3] = 0x4F                  // colour 1: red high nibble F plus its extra low bit
        d += [0, 0]                               // not packed
        var pixels = [UInt8](repeating: 0, count: 64000)
        pixels[1] = 1
        d += pixels
        let image = try PCFormats.loadFliAwayFrame(d)
        XCTAssertTrue(image.pixel(0, 0) == (0, 0, 0))
        XCTAssertTrue(image.pixel(1, 0) == (255, 0, 0))

        var packed = Array(d[0..<512])
        let body = PackBytes.pack(pixels)
        packed += [UInt8(body.count & 0xFF), UInt8(body.count >> 8)] + body
        XCTAssertEqual(try PCFormats.loadFliAwayFrame(packed).rgb, image.rgb)
    }

    func testSunRasterRunLength() throws {
        func long(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        // 4 x 1, 8 bits, RLE, colour map of two entries: black, green.
        var d = long(0x59A66A95) + long(4) + long(1) + long(8) + long(0) + long(2) + long(1) + long(6)
        d += [0, 0, 0, 255, 0, 0]                 // reds, greens, blues
        d += [0x80, 2, 1, 0]                      // three 1s, then a 0
        let image = try UnixFormats.loadSunRaster(d)
        XCTAssertTrue(image.pixel(2, 0) == (0, 255, 0))
        XCTAssertTrue(image.pixel(3, 0) == (0, 0, 0))
    }

    func testSGIIsBottomUp() throws {
        var d = [UInt8](repeating: 0, count: 512)
        d[0] = 0x01; d[1] = 0xDA; d[3] = 1        // verbatim, one byte per channel
        d[5] = 2; d[7] = 2; d[9] = 2; d[11] = 1   // 2 x 2 grey
        d += [10, 20, 30, 40]                     // bottom row first
        let image = try UnixFormats.loadSGI(d)
        XCTAssertTrue(image.pixel(0, 1) == (10, 10, 10))
        XCTAssertTrue(image.pixel(1, 0) == (40, 40, 40))
    }

    func testPortablePixelmaps() throws {
        let text = Array("P3\n# two pixels\n2 1\n15\n15 0 0  0 15 15\n".utf8)
        let a = try UnixFormats.loadPNM(text)
        XCTAssertTrue(a.pixel(0, 0) == (255, 0, 0))
        XCTAssertTrue(a.pixel(1, 0) == (0, 255, 255))
        let raw = Array("P5\n2 1\n255\n".utf8) + [7, 200]
        XCTAssertTrue(try UnixFormats.loadPNM(raw).pixel(1, 0) == (200, 200, 200))
        let bits = Array("P4\n9 1\n".utf8) + [0x80, 0x80]
        let c = try UnixFormats.loadPNM(bits)
        XCTAssertTrue(c.pixel(0, 0) == (0, 0, 0))
        XCTAssertTrue(c.pixel(1, 0) == (255, 255, 255))
        XCTAssertTrue(c.pixel(8, 0) == (0, 0, 0))
    }
}
