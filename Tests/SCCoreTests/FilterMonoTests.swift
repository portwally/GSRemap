import XCTest
@testable import SCCore

final class FilterMonoTests: XCTestCase {
    private func flat(_ v: UInt8, width: Int = 8, height: Int = 8) -> TrueColorImage {
        TrueColorImage(width: width, height: height, rgb: [UInt8](repeating: v, count: width * height * 3))
    }

    /// Grey everywhere with one bright pixel in the middle.
    private func spot() -> TrueColorImage {
        var image = flat(100, width: 5, height: 5)
        image.setPixel(2, 2, 200, 200, 200)
        return image
    }

    func testFlatImagesStayFlat() {
        let image = flat(90)
        XCTAssertEqual(Filters.median(image).rgb, image.rgb)
        XCTAssertEqual(Filters.sigma(image).rgb, image.rgb)
        XCTAssertEqual(Filters.blur(image, factor: 50).rgb, image.rgb)
        XCTAssertEqual(Filters.sharpen(image, factor: 50).rgb, image.rgb)
        XCTAssertTrue(Filters.emboss(image).rgb.allSatisfy { $0 == 128 })
        XCTAssertTrue(Filters.findEdges(image, factor: 50).rgb.allSatisfy { $0 == 0 })
    }

    func testMedianRemovesASpotAndBlurSpreadsIt() {
        XCTAssertTrue(Filters.median(spot()).pixel(2, 2) == (100, 100, 100))
        let blurred = Filters.blur(spot(), factor: 50)
        XCTAssertLessThan(blurred.pixel(2, 2).r, 200)
        XCTAssertGreaterThan(blurred.pixel(1, 2).r, 100)
        // Factor 50: centre weight 12 of 24, so the spot keeps half of its extra brightness.
        XCTAssertEqual(blurred.pixel(2, 2).r, 150)
        // Sigma is an average of all nine: 100 + 100 / 9.
        XCTAssertEqual(Filters.sigma(spot()).pixel(2, 2).r, 111)
    }

    func testSharpenAndEdges() {
        let sharp = Filters.sharpen(spot(), factor: 50)
        XCTAssertGreaterThan(sharp.pixel(2, 2).r, 200)
        XCTAssertLessThan(sharp.pixel(1, 2).r, 100)
        let edges = Filters.findEdges(spot(), factor: 50)
        XCTAssertEqual(edges.pixel(2, 2).r, 255)      // 4 x (200 - 100), clamped
        XCTAssertEqual(edges.pixel(0, 0).r, 0)
    }

    func testSolarizeAndContrast() {
        XCTAssertEqual(Filters.solarize(flat(100)).rgb[0], 100)
        XCTAssertEqual(Filters.solarize(flat(200)).rgb[0], 55)
        XCTAssertLessThan(Filters.contrast(flat(60), increase: true).rgb[0], 60)
        XCTAssertGreaterThan(Filters.contrast(flat(200), increase: true).rgb[0], 200)
        XCTAssertGreaterThan(Filters.contrast(flat(60), increase: false).rgb[0], 60)
        // A pure colour keeps its hue.
        var red = flat(0)
        for i in stride(from: 0, to: red.rgb.count, by: 3) { red.rgb[i] = 200 }
        let out = Filters.contrast(red, increase: true)
        XCTAssertGreaterThan(out.rgb[0], 200)
        XCTAssertEqual(out.rgb[1], 0)
    }

    func testEqualizeStretchesTheRange() {
        var image = flat(0, width: 4, height: 1)
        for (x, v) in [100, 110, 120, 130].enumerated() { image.setPixel(x, 0, UInt8(v), UInt8(v), UInt8(v)) }
        let out = Filters.equalize(image)
        XCTAssertEqual(out.pixel(0, 0).r, 0)
        XCTAssertEqual(out.pixel(3, 0).r, 255)
        XCTAssertEqual(out.pixel(1, 0).r, 85)
    }

    func testToMonochrome() {
        // Mid grey: every method gives about half white; threshold gives all or nothing.
        for method in [MonoRendering.errorDiffusion, .patternDither, .halftone] {
            let mono = MonoConversion.monochrome(from: flat(128, width: 16, height: 16), xScale: 2, yScale: 1, method: method)
            XCTAssertEqual(mono.width, 32)
            XCTAssertEqual(mono.height, 16)
            XCTAssertEqual(Double(mono.whiteCount) / 512, 0.5, accuracy: 0.07, "\(method)")
        }
        XCTAssertEqual(MonoConversion.monochrome(from: flat(127), xScale: 1, yScale: 1, method: .threshold).whiteCount, 0)
        XCTAssertEqual(MonoConversion.monochrome(from: flat(128), xScale: 1, yScale: 1, method: .threshold).whiteCount, 64)
        // Black stays black and white stays white, whatever the method.
        for method in MonoRendering.allCases {
            XCTAssertEqual(MonoConversion.monochrome(from: flat(0), xScale: 1, yScale: 1, method: method).whiteCount, 0)
            XCTAssertEqual(MonoConversion.monochrome(from: flat(255), xScale: 1, yScale: 1, method: method).whiteCount, 64)
        }
    }

    func testFromMonochrome() {
        var mono = MonoImage(width: 4, height: 4)
        mono.pixels[0] = 0                      // one black pixel, top left
        var options = FromMonoOptions()
        options.mode640 = false
        options.aspect = .square
        let exact = MonoConversion.screen(from: mono, options: options)
        XCTAssertEqual(exact.width, 4)
        XCTAssertEqual(Array(exact.pixels[0..<2]), [0, 15])

        options.mode640 = true                  // square pixels need two 640 mode pixels each
        let wide = MonoConversion.screen(from: mono, options: options)
        XCTAssertEqual(wide.width, 8)
        XCTAssertEqual(Array(wide.pixels[0..<3]), [0, 0, 1])
        XCTAssertEqual(wide.colour(2, 0), 0xFFF)

        options.mode640 = false
        options.scaling = 2
        options.shrink = .grayscale             // 3 of 4 white → light grey
        let grey = MonoConversion.screen(from: mono, options: options)
        XCTAssertEqual(grey.width, 2)
        XCTAssertEqual(grey.pixels[0], 11)
        XCTAssertEqual(grey.pixels[1], 15)
        options.shrink = .lineArtOnWhite        // any black keeps the block black
        XCTAssertEqual(MonoConversion.screen(from: mono, options: options).pixels[0], 0)
        options.shrink = .lineArtOnBlack
        XCTAssertEqual(MonoConversion.screen(from: mono, options: options).pixels[0], 15)
        options.shrink = .threshold
        XCTAssertEqual(MonoConversion.screen(from: mono, options: options).pixels[0], 15)

        options.shrink = .grayscale
        let colour = MonoConversion.trueColor(from: mono, options: options)
        XCTAssertTrue(colour.pixel(0, 0) == (191, 191, 191))
        XCTAssertFalse(colour.tallPixels)
    }

    func testNegativeAndCount() {
        var mono = MonoImage(width: 3, height: 1)
        mono.pixels = [1, 0, 0]
        XCTAssertEqual(mono.whiteCount, 1)
        mono.negate()
        XCTAssertEqual(mono.pixels, [0, 1, 1])
    }
}
