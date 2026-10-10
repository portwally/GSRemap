import SCCore
import SwiftUI

@main
struct GSRemapApp: App {
    @StateObject private var model = AppModel()

    init() {
        // `--snapshot <png>` renders the desktop to a file and quits: used to check the layout.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: args[i + 1], demo: args.dropFirst(i + 2).first)
        }
    }

    var body: some Scene {
        WindowGroup("GS Remap") {
            GeometryReader { geo in
                let scale = min(geo.size.width / DesktopView.size.width, geo.size.height / DesktopView.size.height)
                DesktopView(model: model)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color.black)
            }
            .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Load & Convert…") { model.load() }.keyboardShortcut("o")
                Button("Re-convert Last File") { model.reload() }.disabled(!model.canReload)
                Divider()
                Button("Save Conversion…") { model.save() }.keyboardShortcut("s").disabled(model.screen == nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") { model.overlay = .preferences }.keyboardShortcut(",")
            }
            CommandMenu("True Color") {
                Button("Convert to Screen (Remap)…") { model.beginRemap() }
                    .keyboardShortcut("r").disabled(!model.hasImage)
            }
        }
    }
}

@MainActor
enum Snapshot {
    /// A sunset over water, drawn from scratch so screenshots show no one else's artwork.
    static func demoPicture() -> TrueColorImage {
        var image = TrueColorImage(width: 320, height: 200)
        let horizon = 118
        func ridge(_ x: Int, _ base: Double, _ a: Double, _ f: Double, _ p: Double) -> Double {
            base + a * sin(Double(x) * f + p) + a * 0.4 * sin(Double(x) * f * 2.7 + p * 1.9)
        }
        for y in 0..<200 {
            for x in 0..<320 {
                var r = 0.0, g = 0.0, b = 0.0
                let dx = Double(x - 205), dy = Double(y - 92)
                let sun = (dx * dx + dy * dy).squareRoot()
                if y < horizon {
                    let t = Double(y) / Double(horizon)
                    r = 0.10 + 0.90 * t * t
                    g = 0.08 + 0.50 * t * t * t
                    b = 0.35 + 0.15 * (1 - t) - 0.25 * t
                    let glow = max(0, 1 - sun / 110)
                    r += 0.5 * glow; g += 0.35 * glow; b += 0.1 * glow
                    if sun < 26 { (r, g, b) = (1.0, 0.95, 0.6) }
                    if Double(y) > ridge(x, 96, 13, 0.021, 0.6) { (r, g, b) = (0.30, 0.16, 0.34) }
                    if Double(y) > ridge(x, 108, 9, 0.034, 2.1) { (r, g, b) = (0.14, 0.08, 0.20) }
                } else {
                    let t = Double(y - horizon) / Double(200 - horizon)
                    r = 0.55 - 0.45 * t; g = 0.22 - 0.12 * t; b = 0.32 - 0.08 * t
                    let wobble = 5 * sin(Double(y) * 0.9) * t
                    let path = abs(Double(x - 205) + wobble)
                    if path < 26 - 14 * t && (y / 2) % 2 == 0 { (r, g, b) = (1.0, 0.80, 0.42) }
                }
                image.setPixel(x, y, UInt8(min(1, max(0, r)) * 255), UInt8(min(1, max(0, g)) * 255),
                               UInt8(min(1, max(0, b)) * 255))
            }
        }
        return image
    }

    static func run(to path: String, demo: String?) {
        let model = AppModel()
        let image = demoPicture()
        model.trueColor = image
        model.fileName = "Sunset"
        model.screen = Remapper.remap(image, options: RemapOptions(outputWidth: 320, outputHeight: 200))
        model.statistics = image.colourStatistics()
        switch demo {
        case "remap": model.overlay = .remap
        case "menu": model.openMenu = 4
        case "dither640":
            model.settings.mode = .mode640Dither
            model.screen = Remapper.remap(image, options: RemapOptions(
                mode: .mode640Dither, prototype: .defaultColor(.mode640Dither), outputWidth: 640, outputHeight: 200))
            model.overlay = .fullScreen
        case "other": model.overlay = .getOther
        case "prefs": model.overlay = .preferences
        case "help":
            model.helpTopic = 3
            model.overlay = .help
        case "examine":
            model.examineName = "SAMPLE.PIC"
            model.examineBytes = SHRFormats.saveApplePreferred(model.screen!)
            model.overlay = .examine
        case "histogram":
            model.examineName = "SAMPLE.PIC"
            model.examineBytes = SHRFormats.saveApplePreferred(model.screen!)
            model.examineHistogram = true
            model.overlay = .examine
        case "printopts": model.overlay = .printOptions
        case "desk":
            model.useAsDesktop()
            model.activeWindow = 2
            model.openMenu = 7
        case "fonts": model.fontList(continuing: false)
        case "half": model.overlay = .viewer(0)
        case "tomono": model.overlay = .toMono(false)
        case "frommono":
            model.mono = MonoConversion.monochrome(from: image, xScale: 2, yScale: 1, method: .halftone)
            model.showMono = true
            model.overlay = .fromMono(true)
        case "monoview":
            model.mono = MonoConversion.monochrome(from: image, xScale: 2, yScale: 2, method: .errorDiffusion)
            model.showMono = true
        case "emboss":
            model.trueColor = Filters.emboss(image)
            model.showTrueColor = true
        case "monomenu":
            model.mono = MonoConversion.monochrome(from: image, xScale: 1, yScale: 1, method: .threshold)
            model.openMenu = 5
        case "saveicon":
            model.saveIndex = FormatRegistry.saveFormats.firstIndex { $0.id == "icon" } ?? 0
            model.save()
        case "savehex":
            model.saveIndex = FormatRegistry.saveFormats.firstIndex { $0.id == "hex" } ?? 0
            model.save()
        case "text":
            var memory = [UInt8](repeating: 0xA0, count: 1024)
            let lines = ["]CATALOG", "", "/GS.REMAP", "", " NAME           TYPE  BLOCKS", "", " HELLO           BAS       1",
                         " Picture.3200    PIC      75", "", "The quick brown fox (jumps) over 12 dogs!"]
            for (row, line) in lines.enumerated() {
                let base = (row & 7) * 0x80 + (row >> 3) * 0x28
                for (i, c) in line.utf8.prefix(40).enumerated() { memory[base + i] = c | 0x80 }
            }
            for i in 0..<8 { memory[0x80 * 3 + 0x28 + i] = UInt8(0x01 + i) }   // inverse "ABCDEFGH" on row 11
            model.screen = try? AppleIIFormats.loadTextScreen(memory, columns: 40)
            model.overlay = .fullScreen
        case "shaston320": model.appFont = .shaston320
        case "system": model.appFont = .system
        default: break
        }
        let renderer = ImageRenderer(content: DesktopView(model: model))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            try? ModernImage.save(cg, to: URL(fileURLWithPath: path), type: .png)
        }
        exit(0)
    }
}
