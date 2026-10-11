import AppKit
import SCCore
import SwiftUI

enum PaletteChoice: Int, CaseIterable {
    case defaultColor, grayscale, calculated, stored, current, other

    var title: String {
        switch self {
        case .defaultColor: return "Default color"
        case .grayscale: return "Grayscale"
        case .calculated: return "Calculated"
        case .stored: return "Stored palette"
        case .current: return "Picture's current"
        case .other: return "Get other..."
        }
    }
}

/// The scale steps offered while "Integral scaling only" is on: 1:16 up to 4:1.
let scaleSteps: [(Int, Int)] = [
    (1, 16), (1, 12), (1, 10), (1, 8), (1, 6), (1, 5), (1, 4), (1, 3), (2, 5), (1, 2), (3, 5), (2, 3),
    (3, 4), (4, 5), (1, 1), (5, 4), (4, 3), (3, 2), (5, 3), (2, 1), (5, 2), (3, 1), (4, 1),
]

struct RemapSettings {
    var mode = GraphicMode.mode320
    var palette = PaletteChoice.calculated
    var other = [0, 0, 0, 0]
    var algorithm = RenderAlgorithm.patternDither
    var hStep = 14
    var vStep = 14
    var integral = true
    var clipHorizFirst = true
    var clipOneScreen = false
}

enum Overlay: Equatable {
    case remap, getOther, about, preferences, choose, saveOptions, fullScreen, factor(Int), toMono(Bool), fromMono(Bool),
         help, examine, printOptions, viewer(Int), working(String), info(String, String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var categoryIndex = 1
    @Published var formatIndex = 0
    @Published var saveIndex = 2
    @Published var screen: ScreenImage?
    @Published var trueColor: TrueColorImage?
    @Published var showTrueColor = false
    @Published var mono: MonoImage?
    /// Files still waiting from a multiple-file Load.
    @Published var queue: [(URL, LoadFormat)] = []
    @Published var pickingHelp = false
    @Published var helpTopic = 0
    @Published var activeWindow = 0
    @Published var desktopImage: CGImage?
    @Published var examineName = ""
    @Published var examineBytes: [UInt8] = []
    @Published var examineTop = 0
    @Published var examineHistogram = false
    @Published var printScaleText = "100"
    @Published var printCentered = true
    @Published var printAddCaption = false
    @Published var printCaption = ""
    @Published var fontPage = 0
    @Published var moreFonts = false
    var loadDirectory: URL?
    var saveDirectory: URL?
    @Published var showMono = false
    @Published var factorText = "50"
    @Published var monoXScale = 1
    @Published var monoYScale = 1
    @Published var monoMethod = MonoRendering.errorDiffusion
    @Published var fromMono = FromMonoOptions()
    @Published var fileName = ""
    @Published var overlay: Overlay?
    @Published var settings = RemapSettings()
    @Published var openMenu: Int?
    @Published var appFont: AppFont {
        didSet {
            GS.appearance = appFont
            UserDefaults.standard.set(appFont.rawValue, forKey: "appFont")
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appFont").flatMap(AppFont.init(rawValue:))
        appFont = saved ?? .shaston640
        GS.appearance = appFont
        if let url = Bundle.main.url(forResource: "PrintChar21", withExtension: "ttf") {
            AppleIIFormats.loadTextGlyphs(fontURL: url)
        }
    }
    @Published var statistics: (distinct: Int, isGrey: Bool, isBlackAndWhite: Bool)?

    @Published var saveOptions = SaveOptions()
    @Published var iconFileTypeText = "00"
    @Published var iconAuxTypeText = "0000"
    /// Titles and loader for a file that holds several pictures.
    @Published var choices: [String] = []
    @Published var choiceIndex = 0
    private var pickChoice: ((Int) throws -> LoadedImage)?
    private var lastLoad: (URL, LoadFormat)?
    private var stored: (mode: GraphicMode, palette: [Color12])?

    var categories: [LoadCategory] { FormatRegistry.loadCategories }
    var formats: [LoadFormat] { categories[categoryIndex].formats }
    var hasImage: Bool { screen != nil || trueColor != nil || mono != nil }

    var imageTitle: String {
        guard hasImage else { return "No image" }
        guard let screen else { return "\(fileName) (???)" }
        let tables = screen.palettes.count > 16 ? 200 : Set(screen.scbs.map { $0 & 15 }).count
        return "\(fileName) (\(screen.is640 ? "640" : "320"), \(tables) palette\(tables == 1 ? "" : "s"))"
    }

    // MARK: Loading and saving

    /// Load button: several files may be picked; the first loads now, the rest wait for Load next.
    func load() {
        let format = formats[min(formatIndex, formats.count - 1)]
        let panel = NSOpenPanel()
        panel.message = "Load: \(format.name)"
        panel.prompt = "Accept"
        panel.allowsMultipleSelection = true
        panel.directoryURL = loadDirectory
        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        loadDirectory = first.deletingLastPathComponent()
        if panel.urls.count == 1 {
            load(first, format)
        } else {
            queue += panel.urls.map { ($0, format) }
            loadNext()
        }
    }

    func loadNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        load(next.0, next.1)
    }

    func exchangePaths() {
        swap(&loadDirectory, &saveDirectory)
    }

    func paste() {
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let picture = try? ModernImage.trueColor(from: image) else {
            overlay = .info("Paste", "There is no picture on the clipboard.")
            return
        }
        fileName = "Clipboard"
        show(.trueColor(picture))
    }

    func examine() {
        let panel = NSOpenPanel()
        panel.message = "Examine which file?"
        panel.directoryURL = loadDirectory
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        examineName = url.lastPathComponent
        examineBytes = [UInt8](data)
        examineTop = 0
        examineHistogram = false
        overlay = .examine
    }

    func useAsDesktop() {
        guard let screen else { return }
        desktopImage = ModernImage.cgImage(screen)
    }

    func systemInfo() {
        let info = ProcessInfo.processInfo
        var lines = [
            "GS Remap \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")",
            "macOS \(info.operatingSystemVersionString)",
            "Memory: \(info.physicalMemory / 1_048_576) MB, \(info.activeProcessorCount) processors",
            "Load formats: \(categories.reduce(0) { $0 + $1.formats.count }), save formats: \(FormatRegistry.saveFormats.count)",
        ]
        if let screen { lines.append("Screen image: \(screen.width) x \(screen.height), \(screen.is640 ? "640" : "320") mode") }
        if let trueColor { lines.append("True color image: \(trueColor.width) x \(trueColor.height)") }
        if let mono { lines.append("Monochrome image: \(mono.width) x \(mono.height)") }
        if !queue.isEmpty { lines.append("Files waiting to load: \(queue.count)") }
        overlay = .info("System info report", lines.joined(separator: "\n"))
    }

    /// Makes a picture listing installed fonts, each drawn in itself, one page at a time.
    func fontList(continuing: Bool) {
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        let perPage = 28
        if !continuing { fontPage = 0 }
        let slice = Array(families.dropFirst(fontPage * perPage).prefix(perPage))
        guard !slice.isEmpty, let picture = Printing.fontListImage(slice) else { return }
        fontPage += 1
        moreFonts = fontPage * perPage < families.count
        fileName = "Fonts \(fontPage)"
        trueColor = picture
        statistics = nil
        showMono = false
        showTrueColor = true
        activeWindow = 2
    }

    // MARK: Printing

    /// Print (normal): the screen image, as large as fits the page.
    func printNormal() {
        guard let screen, let image = ModernImage.cgImage(screen) else { return }
        Printing.run(.picture(image, scale: nil, centered: true, caption: nil))
    }

    /// Print (enhanced): the best picture in memory with the chosen size, position and caption.
    func printEnhanced() {
        overlay = nil
        let scale = max(1, min(400, Double(printScaleText) ?? 100)) / 100
        let image = trueColor.flatMap { ModernImage.cgImage($0) } ?? screen.flatMap { ModernImage.cgImage($0) }
        guard let image else { return }
        Printing.run(.picture(image, scale: scale, centered: printCentered,
                              caption: printAddCaption && !printCaption.isEmpty ? printCaption : nil))
    }

    func reload() {
        if let lastLoad { load(lastLoad.0, lastLoad.1) }
    }

    var canReload: Bool { lastLoad != nil }

    func load(_ url: URL, _ format: LoadFormat) {
        do {
            let loaded = try format.load(url)
            lastLoad = (url, format)
            fileName = url.deletingPathExtension().lastPathComponent.components(separatedBy: "#")[0]
            statistics = nil
            show(loaded)
        } catch {
            overlay = .info("Load failed", "\(error)")
        }
    }

    private func show(_ loaded: LoadedImage) {
        switch loaded {
        case .screen(let s):
            screen = s
            trueColor = nil
            mono = nil
            showMono = false
            showTrueColor = false
            overlay = .fullScreen
        case .trueColor(let t):
            trueColor = t
            screen = nil
            mono = nil
            showMono = false
            showTrueColor = true
            beginRemap()
        case .monochrome(let m):
            mono = m
            screen = nil
            trueColor = nil
            showTrueColor = false
            showMono = true
            overlay = nil
        case .choice(let titles, let pick):
            choices = titles
            choiceIndex = 0
            pickChoice = pick
            overlay = .choose
        }
    }

    func confirmChoice() {
        guard let pickChoice else { return }
        do {
            show(try pickChoice(choiceIndex))
        } catch {
            overlay = .info("Load failed", "\(error)")
        }
    }

    /// Save button: formats with extra details show their options first.
    func save() {
        guard screen != nil else { return }
        let format = FormatRegistry.saveFormats[saveIndex]
        if format.options == .none {
            finishSave()
        } else {
            if saveOptions.iconName == "*" && !fileName.isEmpty {
                saveOptions.iconName = String(fileName.uppercased().prefix(15))
            }
            iconFileTypeText = String(format: "%02X", saveOptions.iconFileType)
            iconAuxTypeText = String(format: "%04X", saveOptions.iconAuxType)
            overlay = .saveOptions
        }
    }

    func finishSave() {
        guard let screen else { return }
        overlay = nil
        let format = FormatRegistry.saveFormats[saveIndex]
        saveOptions.iconFileType = Int(iconFileTypeText, radix: 16) ?? 0
        saveOptions.iconAuxType = Int(iconAuxTypeText, radix: 16) ?? 0
        let url: URL
        if format.addsToExistingFile {
            let panel = NSOpenPanel()
            panel.message = "Add to which file? (\(format.name))"
            panel.prompt = "Add"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        } else {
            let panel = NSSavePanel()
            panel.message = "Save: \(format.name)"
            panel.directoryURL = saveDirectory
            panel.nameFieldStringValue = (fileName.isEmpty ? "Untitled" : fileName) + format.suffix
            panel.allowsOtherFileTypes = true
            panel.isExtensionHidden = false
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        saveDirectory = url.deletingLastPathComponent()
        do {
            try format.save(screen, url, saveOptions)
        } catch {
            overlay = .info("Save failed", "\(error)")
        }
    }

    func closeImage() {
        screen = nil
        trueColor = nil
        mono = nil
        showMono = false
        statistics = nil
        fileName = ""
    }

    func copyImage() {
        guard let image = currentCGImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        NSPasteboard.general.clearContents()
        if let data = rep.representation(using: .png, properties: [:]) {
            NSPasteboard.general.setData(data, forType: .png)
        }
    }

    func currentCGImage() -> CGImage? {
        if showMono || (screen == nil && trueColor == nil), let mono {
            return ModernImage.cgImage(width: mono.width, height: mono.height, rgba: mono.rgba())
        }
        if showTrueColor || screen == nil, let trueColor { return ModernImage.cgImage(trueColor) }
        if let screen { return ModernImage.cgImage(screen) }
        return nil
    }

    // MARK: Screen menu

    func screenInfo() {
        guard let screen else { return }
        let colours = Set((0..<screen.height).flatMap { y in (0..<screen.width).map { screen.colour($0, y) } }).count
        overlay = .info("Screen image info", """
            Size: \(screen.width) x \(screen.height) pixels
            Graphic mode: \(screen.is640 ? "640" : "320")
            Color tables: \(screen.palettes.count)
            Colors on screen: \(colours)
            """)
    }

    func convertToTrueColor() {
        guard let screen else { return }
        trueColor = screen.toTrueColor()
        statistics = nil
        showMono = false
        showTrueColor = true
    }

    func storePalette() {
        guard let screen else { return }
        let mode: GraphicMode = !screen.is640 ? .mode320
            : (Array(screen.palettes[0][0..<4]) == Array(screen.palettes[0][4..<8]) ? .mode640 : .mode640Dither)
        stored = (mode, screen.palettes[0])
    }

    // MARK: True color menu

    func trueColorInfo() {
        guard let trueColor else { return }
        let s = trueColor.colourStatistics()
        overlay = .info("True color image info", """
            Size: \(trueColor.width) x \(trueColor.height) pixels
            Distinct colors used: \(s.distinct)
            Distribution: \(distribution(s))
            """)
    }

    func distribution(_ s: (distinct: Int, isGrey: Bool, isBlackAndWhite: Bool)) -> String {
        s.isBlackAndWhite ? "black & white" : s.isGrey ? "grayscale" : "full color"
    }

    func transform(_ bits: Int) {
        guard let image = trueColor else { return }
        trueColor = image.transformed(bits)
        statistics = nil
        showTrueColor = true
    }

    // MARK: Filters

    /// Runs a true colour filter off the main thread and shows the result.
    func filter(_ title: String, _ work: @escaping (TrueColorImage) -> TrueColorImage) {
        guard let image = trueColor else { return }
        overlay = .working(title)
        Task.detached(priority: .userInitiated) {
            let result = work(image)
            await MainActor.run {
                self.trueColor = result
                self.statistics = nil
                self.showTrueColor = true
                self.showMono = false
                self.overlay = nil
            }
        }
    }

    /// Blur, sharpen and find edges ask for a factor from 0 to 99 first.
    func runFactorFilter(_ kind: Int) {
        guard let factor = Int(factorText.trimmingCharacters(in: .whitespaces)), (0...99).contains(factor) else {
            overlay = .info("Factor", "Factor must be a number in the range 0-99.")
            return
        }
        switch kind {
        case 0: filter("Blurring image") { Filters.blur($0, factor: factor) }
        case 1: filter("Sharpening image") { Filters.sharpen($0, factor: factor) }
        default: filter("Finding image edges") { Filters.findEdges($0, factor: factor) }
        }
    }

    // MARK: Monochrome

    func monoInfo() {
        guard let mono else { return }
        let total = mono.width * mono.height, white = mono.whiteCount
        overlay = .info("Monochrome image info", """
            Size: \(mono.width) x \(mono.height) pixels
            White pixels: \(white)
            Total pixels: \(total)
            White: \(total == 0 ? 0 : white * 100 / total)%
            """)
    }

    func negateMono() {
        mono?.negate()
        showMono = true
        showTrueColor = false
    }

    func convertToMono(fromScreen: Bool) {
        let source: TrueColorImage?
        if fromScreen { source = screen?.toTrueColor() } else { source = trueColor }
        guard let source else { return }
        let x = monoXScale, y = monoYScale, method = monoMethod
        overlay = .working("Converting to monochrome...")
        Task.detached(priority: .userInitiated) {
            let result = MonoConversion.monochrome(from: source, xScale: x, yScale: y, method: method)
            await MainActor.run {
                self.mono = result
                self.showMono = true
                self.showTrueColor = false
                self.overlay = nil
            }
        }
    }

    func convertFromMono(toScreen: Bool) {
        guard let mono else { return }
        if toScreen {
            screen = MonoConversion.screen(from: mono, options: fromMono)
            showMono = false
            showTrueColor = false
            overlay = .fullScreen
        } else {
            trueColor = MonoConversion.trueColor(from: mono, options: fromMono)
            statistics = nil
            showMono = false
            showTrueColor = true
            overlay = nil
        }
    }

    // MARK: Remap

    func beginRemap() {
        if trueColor == nil, let screen { trueColor = screen.toTrueColor() }
        guard let image = trueColor else { return }
        fitScaleToScreen()
        overlay = .remap
        if statistics == nil {
            Task.detached(priority: .userInitiated) {
                let s = image.colourStatistics()
                await MainActor.run { self.statistics = s }
            }
        }
    }

    var screenWidth: Int { settings.mode.is640 ? 640 : 320 }

    /// Picks the largest scale that still fits one screen, so big pictures start out sensible.
    func fitScaleToScreen() {
        guard let image = trueColor else { return }
        let natural = Remapper.naturalSize(of: image, mode: settings.mode)
        var step = 14
        while step > 0 {
            let (n, d) = scaleSteps[step]
            if natural.width * n / d <= screenWidth && natural.height * n / d <= 200 { break }
            step -= 1
        }
        settings.hStep = step
        settings.vStep = step
    }

    /// Output size before and after clipping.
    func outputSize() -> (wanted: (Int, Int), clipped: (Int, Int)) {
        guard let image = trueColor else { return ((0, 0), (0, 0)) }
        let natural = Remapper.naturalSize(of: image, mode: settings.mode)
        let (hn, hd) = scaleSteps[settings.hStep], (vn, vd) = scaleSteps[settings.vStep]
        let w = max(1, natural.width * hn / hd), h = max(1, natural.height * vn / vd)
        // A screen image can be at most two screens wide and two screens tall.
        var cw = min(w, screenWidth * 2), ch = min(h, 400)
        if settings.clipOneScreen {
            cw = min(cw, screenWidth)
            ch = min(ch, 200)
        }
        let perByte = settings.mode.is640 ? 4 : 2
        func size() -> Int { ((cw + perByte - 1) / perByte) * ch }
        if size() > 65535 {
            if settings.clipHorizFirst {
                cw = max(screenWidth, 65535 / ch * perByte)
                if size() > 65535 { ch = 65535 / ((cw + perByte - 1) / perByte) }
            } else {
                ch = max(200, 65535 / ((cw + perByte - 1) / perByte))
                if size() > 65535 { cw = 65535 / ch * perByte }
            }
        }
        return ((w, h), (cw, ch))
    }

    func prototype(for choice: PaletteChoice) -> PalettePrototype? {
        let mode = settings.mode
        switch choice {
        case .defaultColor: return mode == .multipalette ? nil : .defaultColor(mode)
        case .grayscale: return mode == .multipalette ? nil : .grayscale(mode)
        case .calculated: return .calculated(mode)
        case .stored:
            guard let stored, stored.mode == mode else { return nil }
            return .fixed("Stored palette", palette: stored.palette, mode: mode)
        case .current:
            guard let screen, screen.is640 == mode.is640, mode != .multipalette else { return nil }
            return .fixed("Picture's current", palette: screen.palettes[0], mode: mode)
        case .other:
            if mode == .multipalette { return .calculated(mode) }
            let list = PalettePrototype.others(mode)
            return list[min(settings.other[mode.rawValue], list.count - 1)]
        }
    }

    var errorDiffusionAllowed: Bool {
        settings.mode != .multipalette && (prototype(for: settings.palette)?.isGrey ?? false)
    }

    /// Keeps the palette and algorithm choices valid after the mode or palette changes.
    func normalise() {
        if prototype(for: settings.palette) == nil { settings.palette = .calculated }
        if settings.algorithm == .errorDiffusion && !errorDiffusionAllowed { settings.algorithm = .patternDither }
    }

    func runRemap(quick: Bool) {
        guard let image = trueColor else { return }
        if quick {
            screen = Remapper.quickRemap(image)
            showTrueColor = false
            overlay = .fullScreen
            return
        }
        normalise()
        let sizes = outputSize()
        var source = image
        if sizes.clipped != sizes.wanted {
            source = image.cropped(width: image.width * sizes.clipped.0 / sizes.wanted.0,
                                   height: image.height * sizes.clipped.1 / sizes.wanted.1)
        }
        var options = RemapOptions(mode: settings.mode, prototype: prototype(for: settings.palette),
                                   algorithm: settings.algorithm,
                                   outputWidth: sizes.clipped.0, outputHeight: sizes.clipped.1)
        if settings.mode == .multipalette && settings.palette == .other {
            options.multipalette = MultipaletteOption(rawValue: settings.other[3] + 1) ?? .standard
        }
        overlay = .working("Remapping...")
        Task.detached(priority: .userInitiated) {
            let result = Remapper.remap(source, options: options)
            await MainActor.run {
                self.screen = result
                self.showTrueColor = false
                self.overlay = .fullScreen
            }
        }
    }
}
