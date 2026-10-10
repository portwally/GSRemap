import Foundation
import UniformTypeIdentifiers

public enum LoadedImage {
    case screen(ScreenImage)
    case trueColor(TrueColorImage)
    case monochrome(MonoImage)
    /// The file holds several pictures: the user picks one by title.
    indirect case choice(titles: [String], pick: (Int) throws -> LoadedImage)
}

/// One line in the Load formats window.
public struct LoadFormat: Identifiable {
    public let id: String
    public let name: String
    /// True colour formats are shown with a leading asterisk, as in the original.
    public let trueColor: Bool
    public let load: (URL) throws -> LoadedImage

    public var listName: String { trueColor ? "*" + name : name }
}

public struct LoadCategory: Identifiable {
    public let id: String
    public let name: String
    public let formats: [LoadFormat]
}

public enum SaveOptionsKind {
    case none, icon, iconResource, hex
}

/// One line in the Save formats window.
public struct SaveFormat: Identifiable {
    public let id: String
    public let name: String
    /// Suggested file name ending: a ProDOS type suffix or an ordinary extension.
    public let suffix: String
    /// Which details to ask for before saving.
    public var options = SaveOptionsKind.none
    /// True when the format changes a file that is already there instead of making a new one.
    public var addsToExistingFile = false
    public let save: (ScreenImage, URL, SaveOptions) throws -> Void
}

public enum FormatRegistry {
    static func bytes(_ url: URL) throws -> [UInt8] { [UInt8](try Data(contentsOf: url)) }

    static func screen(_ id: String, _ name: String, _ loader: @escaping ([UInt8]) throws -> ScreenImage) -> LoadFormat {
        LoadFormat(id: id, name: name, trueColor: false) { .screen(try loader(try bytes($0))) }
    }

    /// Black & white pictures too tall for one screen load as monochrome images, as in the original.
    static func screenOrMono(_ id: String, _ name: String,
                             _ loader: @escaping ([UInt8]) throws -> ScreenImage) -> LoadFormat {
        LoadFormat(id: id, name: name, trueColor: false) {
            let s = try loader(try bytes($0))
            guard s.is640, s.height > 200, s.palettes[0][0] == 0x000, s.palettes[0][1] == 0xFFF,
                  s.pixels.allSatisfy({ $0 < 2 }) else { return .screen(s) }
            var mono = MonoImage(width: s.width, height: s.height)
            mono.pixels = s.pixels
            return .monochrome(mono)
        }
    }

    static func modern(_ id: String, _ name: String) -> LoadFormat {
        LoadFormat(id: id, name: name, trueColor: true) { .trueColor(try ModernImage.load($0)) }
    }

    static func trueColor(_ id: String, _ name: String,
                          _ loader: @escaping ([UInt8]) throws -> TrueColorImage) -> LoadFormat {
        LoadFormat(id: id, name: name, trueColor: true) { .trueColor(try loader(try bytes($0))) }
    }

    public static let loadCategories: [LoadCategory] = [
        LoadCategory(id: "a2", name: "Apple II family", formats: [
            screen("hgrbw", "HiRes black & white") { try AppleIIFormats.loadHiResMono($0) },
            screen("hgr", "HiRes color") { try AppleIIFormats.loadHiRes($0) },
            screen("dhrbw", "DoubleHiRes black & white") { try AppleIIFormats.loadDoubleHiRes($0, colour: false) },
            screen("dhr", "DoubleHiRes color") { try AppleIIFormats.loadDoubleHiRes($0, colour: true) },
            screen("psbw", "Print Shop B & W graphic") { try IIgsFormats.loadPrintShop($0) },
            trueColor("tscan", "ThunderScan raw scan file") { try AppleIIFormats.loadThunderScan($0) },
            screen("tdm40", "TDM 40-column text screen capture") { try AppleIIFormats.loadTextScreen($0, columns: 40) },
            screen("tdm80", "TDM 80-column text screen capture") { try AppleIIFormats.loadTextScreen($0, columns: 80) },
        ]),
        LoadCategory(id: "gs", name: "Apple IIgs specific", formats: [
            screen("shr", "SuperHiRes ($C0/PNT, $C1/PIC)") { try SHRFormats.loadAny($0) },
            screen("c1", "Uncompressed SHR screen ($C1, BIN)") { try SHRFormats.loadScreen($0) },
            screen("drm", "DreamGrafix SHR screen") { try IIgsFormats.loadDreamGrafix($0) },
            trueColor("drm3200", "DreamGrafix \"3200 color\" screen") { try IIgsFormats.loadDreamGrafix3200($0) },
            screen("pwgold", "Paintworks Gold 640 mode files") { try IIgsFormats.loadPaintworksGold($0) },
            screen("psgs", "Print Shop IIgs color graphic") { try IIgsFormats.loadPrintShopGS($0) },
            LoadFormat(id: "cgt", name: "PS IIgs built-in (GRAPHIC.CGT0-7)", trueColor: false) {
                try IIgsFormats.loadPrintShopLibrary(try bytes($0))
            },
            LoadFormat(id: "icon", name: "Finder icon file", trueColor: false) {
                try IIgsFormats.loadIconFile(try bytes($0))
            },
            trueColor("ast", "AST picture data file (color only)") { try IIgsFormats.loadAST($0) },
            trueColor("ceyes", "ComputerEyes GS raw data file") { try IIgsFormats.loadComputerEyes($0) },
            trueColor("3200", "\"3200 color\" uncompressed picture") { try SHRFormats.load3200($0).toTrueColor() },
            trueColor("3200c", "\"3200 color\" compressed picture") { try IIgsFormats.load3200Compressed($0) },
        ]),
        LoadCategory(id: "st", name: "Atari ST", formats: [
            screenOrMono("degas", "Degas (.PI1, .PI2, .PI3)") { try AtariFormats.loadDegas($0) },
            screenOrMono("degaselite", "Degas Elite (.PC1, .PC2, .PC3)") { try AtariFormats.loadDegasElite($0) },
            screenOrMono("neo", "Neochrome (.NEO)") { try AtariFormats.loadNeochrome($0) },
            screenOrMono("tiny", "Tiny (.TNY)") { try AtariFormats.loadTiny($0) },
            trueColor("spu", "Spectrum 512 uncompressed (.SPU)") { try AtariFormats.loadSpectrum($0) },
            trueColor("spc", "Spectrum 512 compressed (.SPC)") { try AtariFormats.loadSpectrumCompressed($0) },
        ]),
        LoadCategory(id: "amiga", name: "Amiga", formats: [
            trueColor("iff", "IFF (FORM ILBM only)") { try AmigaFormats.loadIFF($0) },
        ]),
        LoadCategory(id: "c64", name: "Commodore 64/128", formats: [
            screen("doodle", "Doodle (DDxxx)") { try C64Formats.loadDoodle($0) },
            screen("koala", "Koala Illustrator") { try C64Formats.loadKoala($0) },
            screen("c64ps", "Print Shop screen") { try C64Formats.loadPrintShop($0) },
        ]),
        LoadCategory(id: "mac", name: "Macintosh", formats: [
            screen("mpnt640", "MacPaint => 640 mode grayscale") { try MacFormats.loadMacPaint640($0) },
            screen("mpnt320", "MacPaint => 320 mode black & white") { try MacFormats.loadMacPaint320($0) },
            LoadFormat(id: "mpntmono", name: "MacPaint, as monochrome image", trueColor: false) {
                let rows = try MacFormats.macPaintRows(try bytes($0))
                var mono = MonoImage(width: 576, height: 720)
                for y in 0..<720 {
                    for x in 0..<576 where rows[y][x >> 3] & (0x80 >> UInt8(x & 7)) != 0 { mono.pixels[y * 576 + x] = 0 }
                }
                return .monochrome(mono)
            },
            screenOrMono("macsm", "ScreenMaker (old startup screen)") { try MacFormats.loadScreenMaker($0) },
        ]),
        LoadCategory(id: "ibm", name: "IBM PC & compatibles", formats: [
            modern("bmp", "Windows or OS/2 bitmap (.BMP)"),
            trueColor("gem", "Ventura Publisher (.IMG, .GEM)") { try PCFormats.loadGEM($0) },
            trueColor("pcx", "PC Paintbrush (.PCX, .PCC)") { try PCFormats.loadPCX($0) },
            trueColor("lbm", "DeluxePaint, not Enhanced (.LBM)") { try AmigaFormats.loadIFF($0) },
            trueColor("fliaway", "AutoDesk Animator frame file from FliAway") { try PCFormats.loadFliAwayFrame($0) },
        ]),
        LoadCategory(id: "unix", name: "Unix machines", formats: [
            trueColor("sun", "Sun Rasterfile") { try UnixFormats.loadSunRaster($0) },
            trueColor("sgi", "SGI Iris") { try UnixFormats.loadSGI($0) },
            trueColor("pnm", "Portable Pixelmap") { try UnixFormats.loadPNM($0) },
        ]),
        LoadCategory(id: "ind", name: "Computer-independent", formats: [
            modern("jpeg", "JPEG (JFIF)"),
            modern("gif", "GIF (Graphics Interchange Format)"),
            modern("png", "PNG (Portable Network Graphics)"),
            screen("rle", "RLE (Run Length Encoding)") { try IndependentFormats.loadRLE($0) },
            LoadFormat(id: "ipi", name: "IPI image (.R + .G + .B)", trueColor: true) {
                .trueColor(try IndependentFormats.loadIPI($0))
            },
            trueColor("qrt", "QRT raw image file") { try IndependentFormats.loadQRT($0) },
            modern("tiff", "TIFF (Tagged Image File Format)"),
            modern("any", "Anything macOS can open"),
        ]),
    ]

    static func raw(_ id: String, _ name: String, _ suffix: String,
                    _ encode: @escaping (ScreenImage) throws -> [UInt8]) -> SaveFormat {
        SaveFormat(id: id, name: name, suffix: suffix) { screen, url, _ in
            try Data(try encode(screen)).write(to: url)
        }
    }

    static func modernSave(_ id: String, _ name: String, _ ext: String, _ type: UTType) -> SaveFormat {
        SaveFormat(id: id, name: name, suffix: "." + ext) { screen, url, _ in
            guard let image = ModernImage.cgImage(screen) else {
                throw FormatError.unsupported("Can't render the screen image.")
            }
            try ModernImage.save(image, to: url, type: type)
        }
    }

    public static let saveFormats: [SaveFormat] = [
        raw("c00", "$C0,0 PaintWorks+ 1.0 (obsolete)", "#C00000") { try SHRFormats.savePaintWorks($0) },
        raw("c01", "$C0,1 PackBytes (obsolete)", "#C00001") { SHRFormats.savePacked($0) },
        raw("c02", "$C0,2 Apple Preferred", "#C00002") { SHRFormats.saveApplePreferred($0) },
        raw("c1", "$C1 uncompressed screen", "#C10000") { SHRFormats.saveScreen($0) },
        SaveFormat(id: "icon", name: "Finder icon (new file)", suffix: ".ICN#CA0000", options: .icon) { screen, url, options in
            try Data(try IconFormats.newIconFile(screen, options: options)).write(to: url)
        },
        SaveFormat(id: "iconadd", name: "Finder icon (add to file)", suffix: "", options: .icon,
                   addsToExistingFile: true) { screen, url, options in
            let existing = [UInt8](try Data(contentsOf: url))
            try Data(try IconFormats.addIcon(to: existing, screen, options: options)).write(to: url)
        },
        SaveFormat(id: "ricon", name: "Icon resource (new resource file)", suffix: "_ResourceFork.bin",
                   options: .iconResource) { screen, url, options in
            var fork = ResourceFork()
            fork.resources.append(.init(type: 0x8001, id: 1, attributes: 0,
                                        data: try IconFormats.iconResource(screen, options: options)))
            try Data(fork.bytes()).write(to: url)
        },
        SaveFormat(id: "riconadd", name: "Icon resource (add to resource file)", suffix: "", options: .iconResource,
                   addsToExistingFile: true) { screen, url, options in
            var fork = try ResourceFork([UInt8](try Data(contentsOf: url)))
            fork.resources.append(.init(type: 0x8001, id: fork.freeID(type: 0x8001), attributes: 0,
                                        data: try IconFormats.iconResource(screen, options: options)))
            try Data(fork.bytes()).write(to: url)
        },
        SaveFormat(id: "hex", name: "Hex data (for programmers only)", suffix: ".SRC.txt", options: .hex) { screen, url, options in
            try Data(HexFormat.dump(screen, options: options).utf8).write(to: url)
        },
        modernSave("gif", "GIF (Graphics Interchange Format)", "gif", .gif),
        modernSave("png", "PNG (Portable Network Graphics)", "png", .png),
        modernSave("tiff", "TIFF (Tagged Image File Format)", "tiff", .tiff),
    ]
}
