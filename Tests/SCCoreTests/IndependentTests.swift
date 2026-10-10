import XCTest
@testable import SCCore

final class IndependentTests: XCTestCase {
    func testCompuServeRLE() throws {
        // Junk before the picture, then: 3 black, 2 white, 0 black, 1 white, with a line break inside.
        let text = Array("Welcome!\r\n".utf8) + [0x1B, 0x47, 0x48] + Array("#\"\r\n !".utf8) + [0x1B, 0x47, 0x4E]
        let s = try IndependentFormats.loadRLE(text)
        XCTAssertEqual(s.width, 256)
        XCTAssertEqual(s.height, 192)
        XCTAssertEqual(Array(s.pixels[0..<7]), [0, 0, 0, 15, 15, 15, 0])
        let small = try IndependentFormats.loadRLE([0x1B, 0x47, 0x4D, 0x25])
        XCTAssertEqual(small.width, 128)
        XCTAssertEqual(small.height, 96)
        XCTAssertThrowsError(try IndependentFormats.loadRLE(Array("no picture here".utf8)))
    }

    func testIPIFindsItsSiblings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ipi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (letter, value) in [("R", UInt8(10)), ("G", UInt8(20)), ("B", UInt8(30))] {
            var plane = [UInt8](repeating: value, count: 65536)
            plane[257] = value + 1
            try Data(plane).write(to: folder.appendingPathComponent("LENNA.\(letter)"))
        }
        // Picking the green file loads all three.
        let image = try IndependentFormats.loadIPI(folder.appendingPathComponent("LENNA.G"))
        XCTAssertEqual(image.width, 256)
        XCTAssertTrue(image.pixel(0, 0) == (10, 20, 30))
        XCTAssertTrue(image.pixel(1, 1) == (11, 21, 31))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("LENNA.B"))
        XCTAssertThrowsError(try IndependentFormats.loadIPI(folder.appendingPathComponent("LENNA.R")))
    }

    func testQRTLinesCarryTheirNumber() throws {
        // 2 x 2, with line 1 stored before line 0.
        let file: [UInt8] = [2, 0, 2, 0,
                             1, 0, 1, 2, 3, 4, 5, 6,
                             0, 0, 9, 8, 7, 6, 5, 4]
        let image = try IndependentFormats.loadQRT(file)
        XCTAssertTrue(image.pixel(0, 1) == (1, 3, 5))
        XCTAssertTrue(image.pixel(1, 1) == (2, 4, 6))
        XCTAssertTrue(image.pixel(0, 0) == (9, 7, 5))
    }
}
