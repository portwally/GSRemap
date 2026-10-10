import XCTest
@testable import SCCore

final class SaveTests: XCTestCase {
    private func picture() -> ScreenImage {
        var s = ScreenImage(width: 40, height: 12, is640: true)
        for i in 0..<s.pixels.count { s.pixels[i] = UInt8((i / 3 + i / 40) & 3) }
        return s
    }

    private func loaded(_ file: [UInt8], _ index: Int) throws -> ScreenImage {
        guard case .choice(_, let pick) = try IIgsFormats.loadIconFile(file),
              case .screen(let screen) = try pick(index) else { throw FormatError.notThisFormat("icon") }
        return screen
    }

    /// The icon loader adds a white margin of 8 pixels each side and 4 lines top and bottom.
    private func withoutMargin(_ s: ScreenImage) -> [UInt8] {
        var out: [UInt8] = []
        for y in 4..<(s.height - 4) { out += s.pixels[(y * s.width + 8)..<(y * s.width + s.width - 8)] }
        return out
    }

    func testIconFileRoundTrip() throws {
        var options = SaveOptions()
        options.iconName = "MY.PICTURE"
        options.iconFileType = 0xC0
        let file = try IconFormats.newIconFile(picture(), options: options)
        guard case .choice(let titles, _) = try IIgsFormats.loadIconFile(file) else { return XCTFail() }
        XCTAssertEqual(titles, ["MY.PICTURE (large)", "MY.PICTURE (small)"])
        XCTAssertEqual(withoutMargin(try loaded(file, 0)), picture().pixels)
        XCTAssertEqual(word(file, 26 + 82), 0xC0)

        // Adding a second icon keeps the first and ends the file properly.
        options.iconName = "SECOND"
        let two = try IconFormats.addIcon(to: file, picture(), options: options)
        guard case .choice(let more, _) = try IIgsFormats.loadIconFile(two) else { return XCTFail() }
        XCTAssertEqual(more.count, 4)
        XCTAssertEqual(more[2], "SECOND (large)")
        XCTAssertEqual(withoutMargin(try loaded(two, 2)), picture().pixels)
        XCTAssertEqual(Array(two.suffix(2)), [0, 0])
    }

    func testIconLimits() {
        let wide = ScreenImage(width: 320, height: 20, is640: true)
        XCTAssertThrowsError(try IconFormats.newIconFile(wide, options: SaveOptions()))
        let lowRes = ScreenImage(width: 40, height: 20, is640: false)
        XCTAssertThrowsError(try IconFormats.newIconFile(lowRes, options: SaveOptions()))
        XCTAssertNoThrow(try IconFormats.iconResource(lowRes, options: SaveOptions()))
    }

    func testWhiteCanBeTransparent() throws {
        var s = ScreenImage(width: 4, height: 1, is640: true)
        s.pixels = [3, 3, 0, 1]
        var options = SaveOptions()
        options.whiteIsTransparent = true
        let icon = IconFormats.icon(s, options: options)
        XCTAssertEqual(Array(icon[0..<8]), [0x00, 0x80, 1, 0, 1, 0, 2, 0])   // colour, 1 byte, 1 high, 2 wide
        XCTAssertEqual(icon[8], 0xF1)       // image: white, then black + red
        XCTAssertEqual(icon[9], 0x0F)       // mask: first pixel clear
    }

    func testResourceForkRoundTrip() throws {
        var fork = ResourceFork()
        fork.resources.append(.init(type: 0x8006, id: 1, attributes: 0x10, data: Array("\u{5}Hello".utf8)))
        fork.resources.append(.init(type: 0x8001, id: 1, attributes: 0, data: [1, 2, 3, 4]))
        fork.resources.append(.init(type: 0x8001, id: 2, attributes: 0, data: []))
        let bytes = fork.bytes()
        XCTAssertEqual(try ResourceFork(bytes).resources, fork.resources)
        XCTAssertEqual(fork.freeID(type: 0x8001), 3)
        XCTAssertEqual(fork.freeID(type: 0x8009), 1)
        // Header points at the map, the map points at itself, and data follows the map.
        XCTAssertEqual(long(bytes, 4), 140)
        XCTAssertEqual(long(bytes, 140 + 6), 140)
        XCTAssertEqual(long(bytes, 140 + 116 + 6), 140 + long(bytes, 8))
        XCTAssertThrowsError(try ResourceFork([UInt8](repeating: 7, count: 300)))
    }

    func testHexDump() {
        var s = ScreenImage(width: 8, height: 2, is640: false)
        s.pixels = [1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 15, 15, 15, 15]
        XCTAssertEqual(HexFormat.dump(s, options: SaveOptions()), " dc h'12 34 56 78'\n dc h'00 00 FF FF'\n")
        var c = SaveOptions()
        c.hexBefore = "  0x"; c.hexBetween = ", 0x"; c.hexAfter = ","
        XCTAssertEqual(HexFormat.dump(s, options: c).split(separator: "\n")[0], "  0x12, 0x34, 0x56, 0x78,")
    }
}
