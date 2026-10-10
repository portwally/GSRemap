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
    static func run(to path: String, demo: String?) {
        let model = AppModel()
        var image = TrueColorImage(width: 320, height: 200)
        for y in 0..<200 {
            for x in 0..<320 {
                image.setPixel(x, y, UInt8(x * 255 / 319), UInt8(y * 255 / 199), UInt8(255 - x * 255 / 319))
            }
        }
        model.trueColor = image
        model.fileName = "Gradient"
        model.screen = Remapper.remap(image, options: RemapOptions(outputWidth: 320, outputHeight: 200))
        model.statistics = image.colourStatistics()
        switch demo {
        case "remap": model.overlay = .remap
        case "menu": model.openMenu = 4
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
