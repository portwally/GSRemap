import XCTest
@testable import SCCore

final class SCCoreTests: XCTestCase {
    func testDistance() {
        XCTAssertEqual(ColorMath.distance(0x000, 0x000), 0)
        // 3·15 + 4·15 + 2·15 = 135, plus 135 >> 2 = 33
        XCTAssertEqual(ColorMath.distance(0xFFF, 0x000), 168)
        XCTAssertEqual(ColorMath.brightness(0xFFF), 240)
    }

    func testPackBytesRoundTrip() {
        var data = [UInt8](repeating: 0, count: 500)
        data += (0..<300).map { UInt8($0 & 0xFF) }
        data += [UInt8](repeating: 7, count: 5) + [1, 2, 2, 3]
        XCTAssertEqual(PackBytes.unpack(PackBytes.pack(data)), data)
    }

    func testPackBytesRecordTypes() {
        XCTAssertEqual(PackBytes.unpack([0x02, 1, 2, 3, 0x43, 9, 0x81, 1, 2, 3, 4, 0xC0, 5]),
                       [1, 2, 3, 9, 9, 9, 9, 1, 2, 3, 4, 1, 2, 3, 4, 5, 5, 5, 5])
    }

    func testFewColoursAreUsedDirectly() {
        var hist = [UInt16](repeating: 0, count: 4096)
        hist[0x000] = 10
        hist[0xF00] = 10
        hist[0x00F] = 5
        hist[0xFFF] = 3
        let out = PaletteCalculator.calculate(prototype: PalettePrototype.calculated(.mode320).entries, histogram: hist)
        XCTAssertEqual(out.first, 0x000)
        XCTAssertEqual(out.last, 0xFFF)
        XCTAssertTrue(out.contains(0xF00))
        XCTAssertTrue(out.contains(0x00F))
    }

    func testExactColoursMapToThemselves() {
        // A 320-mode picture remapped with its own palette must come back unchanged.
        var screen = ScreenImage(width: 320, height: 20, is640: false)
        for i in 0..<screen.pixels.count { screen.pixels[i] = UInt8((i / 7 + i / 320) & 15) }
        let options = RemapOptions(mode: .mode320, prototype: .defaultColor(.mode320),
                                   algorithm: .patternDither, outputWidth: 320, outputHeight: 20)
        let again = Remapper.remap(screen.toTrueColor(), options: options)
        XCTAssertEqual(again.pixels, screen.pixels)
    }

    func testApplePreferredRoundTrip() throws {
        var screen = ScreenImage(width: 640, height: 30, is640: true)
        for i in 0..<screen.pixels.count { screen.pixels[i] = UInt8((i / 5) & 3) }
        let loaded = try SHRFormats.loadApplePreferred(SHRFormats.saveApplePreferred(screen))
        XCTAssertEqual(loaded.pixels, screen.pixels)
        XCTAssertEqual(loaded.palettes, screen.palettes)
        XCTAssertTrue(loaded.is640)
    }

    func testScreenRoundTrip() throws {
        var screen = ScreenImage(width: 320, height: 200, is640: false)
        for i in 0..<screen.pixels.count { screen.pixels[i] = UInt8((i * 7) & 15) }
        XCTAssertEqual(try SHRFormats.loadScreen(SHRFormats.saveScreen(screen)).pixels, screen.pixels)
        XCTAssertEqual(try SHRFormats.loadPacked(SHRFormats.savePacked(screen)).pixels, screen.pixels)
        XCTAssertEqual(try SHRFormats.loadPaintWorks(SHRFormats.savePaintWorks(screen)).pixels, screen.pixels)
    }

    func testGreyErrorDiffusionKeepsAverage() {
        var image = TrueColorImage(width: 64, height: 64)
        for i in 0..<image.rgb.count { image.rgb[i] = 73 }
        let options = RemapOptions(mode: .mode320, prototype: PalettePrototype.others(.mode320)[0],
                                   algorithm: .errorDiffusion, outputWidth: 64, outputHeight: 64)
        let screen = Remapper.remap(image, options: options)
        let white = screen.pixels.filter { $0 == 15 }.count
        XCTAssertTrue(screen.pixels.allSatisfy { $0 == 0 || $0 == 15 })
        // 73/255 of the pixels should be white, give or take.
        XCTAssertEqual(Double(white) / 4096.0, 73.0 / 255.0, accuracy: 0.03)
    }
}
