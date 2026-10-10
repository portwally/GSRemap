import Foundation

/// The four choices in the Remap dialog's "Graphic mode" box.
public enum GraphicMode: Int, CaseIterable {
    case mode320 = 0, mode640, mode640Dither, multipalette

    public var title: String {
        switch self {
        case .mode320: return "320 x 200, 16 colors"
        case .mode640: return "640 x 200, 4 colors"
        case .mode640Dither: return "640 x 200 dither mode"
        case .multipalette: return "Multipalette modes"
        }
    }

    public var is640: Bool { self == .mode640 || self == .mode640Dither }
    /// Number of palette entries a prototype for this mode has.
    public var entryCount: Int {
        switch self {
        case .mode320, .multipalette: return 16
        case .mode640: return 4
        case .mode640Dither: return 8
        }
    }
}

public enum RenderAlgorithm: Int, CaseIterable {
    case closestMatch = 0, patternDither, errorDiffusion

    public var title: String {
        switch self {
        case .closestMatch: return "Closest match"
        case .patternDither: return "Pattern dither"
        case .errorDiffusion: return "Error diffusion"
        }
    }
}

/// Technique used to build palettes in multipalette mode ("Get other…" in that mode).
public enum MultipaletteOption: Int, CaseIterable {
    case standard = 0, max8, optimized, zones, zonesMax8

    public var title: String {
        switch self {
        case .standard: return "Calculated"
        case .max8: return "Use no more than 8 palettes"
        case .optimized: return "Optimized palette selection (takes forever)"
        case .zones: return "Zone division"
        case .zonesMax8: return "Zone division, maximum 8 palettes"
        }
    }

    public var maxPalettes: Int { self == .max8 || self == .zonesMax8 ? 8 : 16 }
}

/// A palette with per-slot instructions for the remapper.
public struct PalettePrototype: Equatable {
    /// Slot is left alone: the remap never uses it.
    public static let reserved: UInt16 = 0x8000
    /// Slot is filled in by the palette calculator.
    public static let calculate: UInt16 = 0x4000

    public var name: String
    /// `$0RGB` plus the flag bits above.
    public var entries: [UInt16]

    public init(_ name: String, _ entries: [UInt16]) {
        self.name = name
        self.entries = entries
    }

    public var needsCalculation: Bool {
        entries.contains { $0 & 0xC000 == PalettePrototype.calculate }
    }

    /// True when every usable entry is a grey: this is what enables error diffusion.
    public var isGrey: Bool {
        if needsCalculation { return false }
        return entries.allSatisfy { $0 & PalettePrototype.reserved != 0 || ColorMath.isGrey($0 & 0x0FFF) }
    }

    // MARK: Built-in palettes (original tables at 08/981E… and 09/0000…)

    public static func defaultColor(_ mode: GraphicMode) -> PalettePrototype {
        switch mode {
        case .mode320, .multipalette:
            return PalettePrototype("Default color", ScreenImage.standard320)
        case .mode640:
            return PalettePrototype("Default color", [0x000, 0xF00, 0x0F0, 0xFFF])
        case .mode640Dither:
            return PalettePrototype("Default color", [0x000, 0xF00, 0x0F0, 0xFFF, 0x000, 0x00F, 0xFF0, 0xFFF])
        }
    }

    public static func grayscale(_ mode: GraphicMode) -> PalettePrototype {
        switch mode {
        case .mode320, .multipalette:
            return PalettePrototype("Grayscale", (0..<16).map { UInt16($0 * 0x111) })
        case .mode640:
            return PalettePrototype("Grayscale", [0x000, 0x777, 0xCCC, 0xFFF])
        case .mode640Dither:
            return PalettePrototype("Grayscale", [0x000, 0x888, 0xDDD, 0xFFF, 0x000, 0x444, 0xBBB, 0xFFF])
        }
    }

    public static func calculated(_ mode: GraphicMode) -> PalettePrototype {
        switch mode {
        case .mode320, .multipalette:
            return PalettePrototype("Calculated", [
                0x0000, 0x4777, 0x4841, 0x472C, 0x400F, 0x4080, 0x4F70, 0x4D00,
                0x4FA9, 0x4FF0, 0x40E0, 0x44DF, 0x4DAF, 0x478F, 0x4CCC, 0x0FFF,
            ])
        case .mode640:
            return PalettePrototype("Calculated", [0x0000, 0x4F00, 0x40F0, 0x0FFF])
        case .mode640Dither:
            return PalettePrototype("Calculated", [0x0000, 0x4F00, 0x40F0, 0x0FFF, 0x0000, 0x400F, 0x4FF0, 0x0FFF])
        }
    }

    /// The "Get other…" list for a mode (multipalette has technique options instead).
    public static func others(_ mode: GraphicMode) -> [PalettePrototype] {
        switch mode {
        case .mode320:
            return [
                PalettePrototype("Black & white only", [
                    0x0000, 0x8777, 0x8841, 0x872C, 0x800F, 0x8080, 0x8F70, 0x8D00,
                    0x8FA9, 0x8FF0, 0x80E0, 0x84DF, 0x8DAF, 0x878F, 0x8CCC, 0x0FFF,
                ]),
                PalettePrototype("Apple II LoRes/Double HiRes colors", [
                    0x0000, 0x0D03, 0x0852, 0x0F60, 0x0070, 0x0555, 0x00D0, 0x0FF0,
                    0x0009, 0x0D0D, 0x0AAA, 0x0F98, 0x022F, 0x06AF, 0x00F9, 0x0FFF,
                ]),
                PalettePrototype("Apple II HiRes colors", [
                    0x0000, 0x8D03, 0x8852, 0x0F60, 0x8070, 0x8555, 0x00D0, 0x8FF0,
                    0x8009, 0x0D0D, 0x8AAA, 0x8F98, 0x022F, 0x86AF, 0x80F9, 0x0FFF,
                ]),
                PalettePrototype("Calculate 14, leave 2 colors for editing", [
                    0x0000, 0x4777, 0x4841, 0x472C, 0x400F, 0x4080, 0x4F70, 0x4D00,
                    0x4FA9, 0x4FF0, 0x40E0, 0x44DF, 0x4DAF, 0x878F, 0x8CCC, 0x0FFF,
                ]),
                PalettePrototype("Calculate 9, leave 7 colors for editing", [
                    0x0000, 0x4777, 0x4841, 0x472C, 0x400F, 0x4080, 0x4F70, 0x4D00,
                    0x8FA9, 0x8FF0, 0x80E0, 0x84DF, 0x8DAF, 0x878F, 0x8CCC, 0x0FFF,
                ]),
                PalettePrototype("Palette used by Quick Remap", quickRemap),
            ]
        case .mode640:
            return [
                PalettePrototype("Black & white only", [0x0000, 0x8F00, 0x80F0, 0x0FFF]),
                PalettePrototype("Black, cyan, magenta, yellow", [0x0000, 0x00FF, 0x0F0F, 0x0FF0]),
                PalettePrototype("Red, green, blue, white", [0x0F00, 0x00F0, 0x000F, 0x0FFF]),
                PalettePrototype("3 level grayscale, leave a color for editing", [0x0000, 0x8F00, 0x0AAA, 0x0FFF]),
            ]
        case .mode640Dither:
            return [
                PalettePrototype("Black & white only", [0x0000, 0x8F00, 0x80F0, 0x0FFF, 0x0000, 0x800F, 0x8FF0, 0x0FFF]),
                PalettePrototype("Backwards default colors, for flipped images",
                                 [0x0000, 0x000F, 0x0FF0, 0x0FFF, 0x0000, 0x0F00, 0x00F0, 0x0FFF]),
                PalettePrototype("Grayscale, leave a color for editing",
                                 [0x0000, 0x8F00, 0x0777, 0x0FFF, 0x0000, 0x800F, 0x0CCC, 0x0FFF]),
            ]
        case .multipalette:
            return []
        }
    }

    public static let quickRemap: [UInt16] = [
        0x0000, 0x000F, 0x00F0, 0x00FF, 0x0F00, 0x0F0F, 0x0FF0, 0x8FFF,
        0x8000, 0x0222, 0x0444, 0x0666, 0x0999, 0x0BBB, 0x0DDD, 0x0FFF,
    ]

    /// A prototype that reuses an existing screen palette as is.
    public static func fixed(_ name: String, palette: [Color12], mode: GraphicMode) -> PalettePrototype {
        switch mode {
        case .mode320, .multipalette: return PalettePrototype(name, Array(palette.prefix(16)))
        case .mode640: return PalettePrototype(name, Array(palette[8..<12]))
        case .mode640Dither: return PalettePrototype(name, Array(palette[8..<16]))
        }
    }
}
