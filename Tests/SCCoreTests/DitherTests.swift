import XCTest
@testable import SCCore

final class DitherTests: XCTestCase {
    private func gradient() -> TrueColorImage {
        var image = TrueColorImage(width: 160, height: 40)
        for y in 0..<40 {
            for x in 0..<160 { image.setPixel(x, y, UInt8(x), UInt8(100 + y * 3), UInt8(255 - x)) }
        }
        return image
    }

    func test640DitherUsesColumnPalettes() {
        let entries = PalettePrototype.defaultColor(.mode640Dither).entries
        let table = PatternTable(palette: entries, pattern: true)
        // Pure blue only exists in the odd-column palette; even columns fall back to black.
        let blue = table.lookup(colour: 0x00F)
        XCTAssertEqual((0..<4).map { table.paletteSlot(byte: blue.even, column: $0) }, [0, 5, 0, 5])
        let white = table.lookup(colour: 0xFFF)
        XCTAssertEqual(white.even, 0xFF)
        XCTAssertEqual(white.odd, 0xFF)
    }

    func testReservedSlotsAreNeverUsed() {
        for mode in [GraphicMode.mode320, .mode640, .mode640Dither] {
            let prototype = PalettePrototype.others(mode)[0]   // Black & white only
            for algorithm in RenderAlgorithm.allCases {
                let size = Remapper.naturalSize(of: gradient(), mode: mode)
                let options = RemapOptions(mode: mode, prototype: prototype, algorithm: algorithm,
                                           outputWidth: size.width, outputHeight: size.height)
                let screen = Remapper.remap(gradient(), options: options)
                let white = UInt8(mode == .mode320 ? 15 : 3)
                XCTAssertTrue(screen.pixels.allSatisfy { $0 == 0 || $0 == white }, "\(mode) \(algorithm)")
                XCTAssertTrue(screen.pixels.contains(0) && screen.pixels.contains(white))
            }
        }
    }

    func testCalculatedPaletteRunsBlackToWhite() {
        let options = RemapOptions(mode: .mode320, outputWidth: 160, outputHeight: 40)
        let screen = Remapper.remap(gradient(), options: options)
        let table = screen.palettes[0]
        XCTAssertEqual(table.first, 0x000)
        XCTAssertEqual(table.last, 0xFFF)
        XCTAssertEqual(Set(table).count, 16)
    }

    func testMultipaletteAssignsEveryLine() {
        let options = RemapOptions(mode: .multipalette, outputWidth: 160, outputHeight: 40)
        let screen = Remapper.remap(gradient(), options: options)
        XCTAssertEqual(screen.palettes.count, 16)
        XCTAssertTrue(screen.scbs.allSatisfy { $0 < 16 })
        XCTAssertGreaterThan(Set(screen.scbs).count, 1)
    }
}
