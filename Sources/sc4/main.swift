import Foundation
import SCCore
import UniformTypeIdentifiers

// Command-line front end to the conversion engine, mainly for testing.
//   sc4 view  <shr file> <out.png>
//   sc4 refork <resource fork> <out>     (rewrite a IIgs resource fork)
//   sc4 load  <file> <out.png> <format id> [picture number]   (any format in the Load formats list;
//             out.rgb: raw RGB at the picture's size, for checks against MegaconvertGS)
//   sc4 remap <picture> <out> [--mode 320|640|640d|multi] [--palette default|gray|calc|other:N]
//                             [--alg closest|pattern|error] [--size WxH] [--quick]
// <out> ends in .png (preview) or .c1 / .packed / .apf / .pw (SHR formats).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func bytes(_ path: String) -> [UInt8] {
    guard let d = FileManager.default.contents(atPath: path) else { fail("Can't read \(path)") }
    return [UInt8](d)
}

/// Raw RGB, row by row (the picture's own size): for checks against other programs.
func rgb(_ screen: ScreenImage) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(screen.width * screen.height * 3)
    for y in 0..<screen.height {
        for x in 0..<screen.width {
            let c = Int(screen.colour(x, y))
            out += [UInt8((c >> 8 & 15) * 17), UInt8((c >> 4 & 15) * 17), UInt8((c & 15) * 17)]
        }
    }
    return out
}

func write(_ screen: ScreenImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    switch url.pathExtension.lowercased() {
    case "rgb": try Data(rgb(screen)).write(to: url)
    case "png":
        guard let image = ModernImage.cgImage(screen) else { fail("Can't render") }
        try ModernImage.save(image, to: url, type: .png)
    case "c1": try Data(SHRFormats.saveScreen(screen)).write(to: url)
    case "packed": try Data(SHRFormats.savePacked(screen)).write(to: url)
    case "pw": try Data(SHRFormats.savePaintWorks(screen)).write(to: url)
    default: try Data(SHRFormats.saveApplePreferred(screen)).write(to: url)
    }
}

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "list" {
    // The load formats by category, as JSON: used for the homepage's interactive Load formats window.
    let categories = FormatRegistry.loadCategories.map { c -> [String: Any] in
        ["id": c.id, "name": c.name, "formats": c.formats.map { ["id": $0.id, "name": $0.listName, "info": FormatInfo.load[$0.id] ?? ""] }]
    }
    let data = try JSONSerialization.data(withJSONObject: categories, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
guard args.count >= 3 else { fail("usage: sc4 view|remap <in> <out> [options]") }
let command = args.removeFirst(), input = args.removeFirst(), output = args.removeFirst()

do {
    switch command {
    case "view":
        try write(try SHRFormats.loadAny(bytes(input)), to: output)
    case "refork":
        // Reads an Apple IIgs resource fork and writes it back out: a check on the writer.
        let fork = try ResourceFork(bytes(input))
        try Data(fork.bytes()).write(to: URL(fileURLWithPath: output))
        print("\(fork.resources.count) resources")
    case "load":
        guard let id = args.first,
              let format = FormatRegistry.loadCategories.flatMap(\.formats).first(where: { $0.id == id }) else {
            fail("formats: " + FormatRegistry.loadCategories.flatMap(\.formats).map(\.id).joined(separator: " "))
        }
        var loaded = try format.load(URL(fileURLWithPath: input))
        if case .choice(let titles, let pick) = loaded {
            print(titles.enumerated().map { "\($0): \($1)" }.joined(separator: ", "))
            loaded = try pick(args.count > 1 ? Int(args[1]) ?? 0 : 0)
        }
        switch loaded {
        case .screen(let screen):
            print("screen \(screen.width)x\(screen.height) \(screen.is640 ? "640" : "320") mode, \(screen.palettes.count) color tables")
            try write(screen, to: output)
        case .trueColor(let image):
            print("true color \(image.width)x\(image.height)")
            if output.lowercased().hasSuffix(".rgb") { try Data(image.rgb).write(to: URL(fileURLWithPath: output)); break }
            guard let cg = ModernImage.cgImage(image) else { fail("Can't render") }
            try ModernImage.save(cg, to: URL(fileURLWithPath: output), type: .png)
        case .monochrome(let mono):
            print("monochrome \(mono.width)x\(mono.height), \(mono.whiteCount) white pixels")
            if output.lowercased().hasSuffix(".rgb") {
                try Data(mono.pixels.flatMap { $0 != 0 ? [255, 255, 255] as [UInt8] : [0, 0, 0] }).write(to: URL(fileURLWithPath: output)); break
            }
            guard let cg = ModernImage.cgImage(width: mono.width, height: mono.height, rgba: mono.rgba()) else { fail("Can't render") }
            try ModernImage.save(cg, to: URL(fileURLWithPath: output), type: .png)
        case .choice: fail("Nested choice")
        }
    case "save":
        // sc4 save <picture> <out> <load format id> <save format id> [dither 0-2] [fit 0/1]
        guard args.count >= 2,
              let lf = FormatRegistry.loadCategories.flatMap(\.formats).first(where: { $0.id == args[0] }),
              let sf = FormatRegistry.saveFormats.first(where: { $0.id == args[1] }) else { fail("formats?") }
        guard case .screen(let screen) = try lf.load(URL(fileURLWithPath: input)) else { fail("not a screen image") }
        var options = SaveOptions()
        if args.count > 2 { options.appleIIDither = Int(args[2]) ?? 0 }
        if args.count > 3 { options.appleIIKeepProportions = args[3] == "1" }
        try sf.save(screen, URL(fileURLWithPath: output), options)
    case "remap":
        var mode = GraphicMode.mode320
        var palette = "calc"
        var algorithm = RenderAlgorithm.patternDither
        var size: (Int, Int)?
        var quick = false
        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--quick": quick = true
            case "--mode":
                switch args.removeFirst() {
                case "640": mode = .mode640
                case "640d": mode = .mode640Dither
                case "multi": mode = .multipalette
                default: mode = .mode320
                }
            case "--palette": palette = args.removeFirst()
            case "--alg":
                switch args.removeFirst() {
                case "closest": algorithm = .closestMatch
                case "error": algorithm = .errorDiffusion
                default: algorithm = .patternDither
                }
            case "--size":
                let parts = args.removeFirst().split(separator: "x").compactMap { Int($0) }
                if parts.count == 2 { size = (parts[0], parts[1]) }
            default: fail("Unknown option \(flag)")
            }
        }
        let image: TrueColorImage
        if let screen = try? SHRFormats.loadAny(bytes(input)), URL(fileURLWithPath: input).pathExtension.isEmpty {
            image = screen.toTrueColor()
        } else {
            image = try ModernImage.load(URL(fileURLWithPath: input))
        }
        if quick {
            try write(Remapper.quickRemap(image), to: output)
            break
        }
        let prototype: PalettePrototype
        if palette == "default" {
            prototype = .defaultColor(mode)
        } else if palette == "gray" {
            prototype = .grayscale(mode)
        } else if palette.hasPrefix("other:"), let n = Int(palette.dropFirst(6)),
                  PalettePrototype.others(mode).indices.contains(n) {
            prototype = PalettePrototype.others(mode)[n]
        } else {
            prototype = .calculated(mode)
        }
        let natural = Remapper.naturalSize(of: image, mode: mode)
        let options = RemapOptions(mode: mode, prototype: prototype, algorithm: algorithm,
                                   outputWidth: size?.0 ?? natural.width, outputHeight: size?.1 ?? natural.height)
        let started = Date()
        let screen = Remapper.remap(image, options: options)
        print("remapped to \(screen.width)x\(screen.height) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        print("palette 0: " + screen.palettes[0].map { String(format: "%03X", $0) }.joined(separator: " "))
        try write(screen, to: output)
    default:
        fail("Unknown command \(command)")
    }
} catch {
    fail("\(error)")
}
