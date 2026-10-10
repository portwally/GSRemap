import Foundation

/// Extra details some save formats ask for before saving.
public struct SaveOptions {
    /// Finder icon: the file name (wildcards allowed) the icon is used for.
    public var iconName = "*"
    public var iconFileType = 0
    public var iconAuxType = 0
    /// Finder icon: path of the program opened when the icon is double-clicked.
    public var iconApplication = ""
    /// Icons: false lets the Finder recolour the icon.
    public var iconColor = true
    public var whiteIsTransparent = false
    /// Hex data: text before, between and after the bytes of each line (original defaults).
    public var hexBefore = " dc h'"
    public var hexBetween = " "
    public var hexAfter = "'"

    public init() {}
}

/// QuickDraw II icons, as used in Finder icon files and rIcon resources.
public enum IconFormats {
    /// Icon record: type, size, height, width, image, mask. Pixels are 4 bits each; in a
    /// 640 mode picture one icon pixel is a pair of screen pixels.
    static func icon(_ screen: ScreenImage, options: SaveOptions) -> [UInt8] {
        let width = screen.is640 ? (screen.width + 1) / 2 : screen.width
        let rowBytes = (width + 1) / 2
        var image = [UInt8](repeating: 0, count: rowBytes * screen.height)
        var mask = image
        for y in 0..<screen.height {
            for x in 0..<width {
                var value: UInt8
                if screen.is640 {
                    let left = screen.pixels[y * screen.width + x * 2] & 3
                    let right = x * 2 + 1 < screen.width ? screen.pixels[y * screen.width + x * 2 + 1] & 3 : 3
                    value = left << 2 | right
                } else {
                    value = screen.pixels[y * screen.width + x] & 15
                }
                let shift = UInt8(x & 1 == 0 ? 4 : 0)
                image[y * rowBytes + x / 2] |= value << shift
                if !(options.whiteIsTransparent && value == 15) { mask[y * rowBytes + x / 2] |= 15 << shift }
            }
        }
        var out: [UInt8] = []
        putWord(&out, options.iconColor ? 0x8000 : 0)
        putWord(&out, image.count)
        putWord(&out, screen.height)
        putWord(&out, width)
        return out + image + mask
    }

    /// A reduced copy for the Finder's small-icon views (the original had a drawing editor here).
    static func reduced(_ screen: ScreenImage) -> ScreenImage {
        let targetWidth = screen.is640 ? 16 : 8, targetHeight = 8
        let step = max(1, max((screen.width + targetWidth - 1) / targetWidth, (screen.height + targetHeight - 1) / targetHeight))
        // Keep 640 mode pixel pairs together so dithered colours survive.
        let unit = screen.is640 ? 2 : 1
        let w = max(unit, (screen.width / step) / unit * unit), h = max(1, screen.height / step)
        var small = ScreenImage(width: w, height: h, is640: screen.is640, palettes: screen.palettes)
        for y in 0..<h {
            for x in 0..<w {
                let sx = min(screen.width - 1, (x / unit) * step * unit + x % unit), sy = min(screen.height - 1, y * step)
                small.pixels[y * w + x] = screen.pixels[sy * screen.width + sx]
            }
        }
        return small
    }

    static func pascal(_ text: String, field: Int) -> [UInt8] {
        let bytes = Array(text.utf8.prefix(field - 1))
        return [UInt8(bytes.count)] + bytes + [UInt8](repeating: 0, count: field - 1 - bytes.count)
    }

    static func checkFinderIcon(_ screen: ScreenImage) throws {
        guard screen.is640 else {
            throw FormatError.unsupported("Finder icons must be 640 mode. Remap the picture to 640 x 200 dither mode with the default palette first.")
        }
        guard screen.width <= 160, screen.height <= 50 else {
            throw FormatError.unsupported("This picture is \(screen.width) x \(screen.height). A Finder icon can't be larger than 160 x 50; 80 x 25 is the usual limit.")
        }
    }

    static func record(_ screen: ScreenImage, options: SaveOptions) -> [UInt8] {
        var body = pascal(options.iconApplication, field: 64) + pascal(options.iconName, field: 16)
        putWord(&body, options.iconFileType)
        putWord(&body, options.iconAuxType)
        body += icon(screen, options: options) + icon(reduced(screen), options: options)
        var out: [UInt8] = []
        putWord(&out, body.count + 2)
        return out + body
    }

    /// A new Finder icon file ($CA) holding one icon.
    public static func newIconFile(_ screen: ScreenImage, options: SaveOptions) throws -> [UInt8] {
        try checkFinderIcon(screen)
        var out = [UInt8](repeating: 0, count: 26)
        out[4] = 1
        return out + record(screen, options: options) + [0, 0]
    }

    /// Adds one icon to the end of an existing Finder icon file.
    public static func addIcon(to file: [UInt8], _ screen: ScreenImage, options: SaveOptions) throws -> [UInt8] {
        try checkFinderIcon(screen)
        guard file.count >= 28, word(file, 4) == 1 else { throw FormatError.notThisFormat("a Finder icon file") }
        var at = 26
        while at + 2 <= file.count {
            let length = word(file, at)
            if length == 0 { break }
            guard at + length <= file.count else { throw FormatError.notThisFormat("a Finder icon file") }
            at += length
        }
        return Array(file[0..<at]) + record(screen, options: options) + [0, 0]
    }

    /// rIcon ($8001) resource body. The original's only limit is a quarter of a screen.
    public static func iconResource(_ screen: ScreenImage, options: SaveOptions) throws -> [UInt8] {
        let data = icon(screen, options: options)
        guard (data.count - 8) / 2 <= 8000 else {
            throw FormatError.unsupported("An icon resource can't be larger than a quarter of the screen.")
        }
        return data
    }
}

/// An Apple IIgs resource fork, held as a plain file on the Mac.
public struct ResourceFork {
    public struct Resource: Equatable {
        public var type: Int
        public var id: Int
        public var attributes: Int
        public var data: [UInt8]
    }

    public var resources: [Resource] = []

    public init() {}

    public init(_ d: [UInt8]) throws {
        guard d.count >= 140 else { throw FormatError.notThisFormat("an Apple IIgs resource fork") }
        let map = long(d, 4)
        guard long(d, 0) == 0, map >= 140, map + 32 <= d.count else {
            throw FormatError.notThisFormat("an Apple IIgs resource fork")
        }
        let index = map + word(d, map + 14), used = long(d, map + 24)
        guard used < 100_000, index + used * 20 <= d.count else {
            throw FormatError.notThisFormat("an Apple IIgs resource fork")
        }
        var found = 0
        var p = index
        while found < used && p + 20 <= d.count {
            let type = word(d, p)
            if type != 0 {
                let offset = long(d, p + 6), size = long(d, p + 12)
                guard offset + size <= d.count else { throw FormatError.notThisFormat("an Apple IIgs resource fork") }
                resources.append(Resource(type: type, id: long(d, p + 2), attributes: word(d, p + 10),
                                          data: Array(d[offset..<(offset + size)])))
                found += 1
            }
            p += 20
        }
    }

    /// Lowest unused ID for a type, starting at 1.
    public func freeID(type: Int) -> Int {
        let taken = Set(resources.filter { $0.type == type }.map(\.id))
        var id = 1
        while taken.contains(id) { id += 1 }
        return id
    }

    /// File image laid out the way GS/OS writes one: header, map, then the resource data.
    public func bytes() -> [UInt8] {
        let slots = resources.count + 10, freeSlots = 10
        let toIndex = 32 + freeSlots * 8 + 4
        let mapSize = toIndex + slots * 20 + 2
        let mapStart = 140
        var out: [UInt8] = []
        putLong(&out, 0)
        putLong(&out, mapStart)
        putLong(&out, mapSize)
        out += [UInt8](repeating: 0, count: 128)

        var offsets: [Int] = []
        var cursor = mapStart + mapSize
        for r in resources {
            offsets.append(cursor)
            cursor += r.data.count
        }
        var map: [UInt8] = []
        putLong(&map, 0)                    // mapNext: filled in by the system in memory
        putWord(&map, 0)
        putLong(&map, mapStart)
        putLong(&map, mapSize)
        putWord(&map, toIndex)
        putWord(&map, 0)
        putWord(&map, 0)
        putLong(&map, slots)
        putLong(&map, resources.count)
        putWord(&map, freeSlots)
        putWord(&map, 1)
        putLong(&map, cursor)               // one free block: everything past the end of file
        putLong(&map, 0xFFFF_FFFF - cursor)
        map += [UInt8](repeating: 0, count: toIndex - map.count)
        for (i, r) in resources.enumerated() {
            putWord(&map, r.type)
            putLong(&map, r.id)
            putLong(&map, offsets[i])
            putWord(&map, r.attributes)
            putLong(&map, r.data.count)
            putLong(&map, 0)
        }
        map += [UInt8](repeating: 0, count: mapSize - map.count)
        out += map
        for r in resources { out += r.data }
        return out
    }
}

public enum HexFormat {
    /// One line of text per picture line: the packed SHR bytes in hexadecimal.
    public static func dump(_ screen: ScreenImage, options: SaveOptions) -> String {
        (0..<screen.height).map { y in
            options.hexBefore
                + screen.packedRow(y).map { String(format: "%02X", $0) }.joined(separator: options.hexBetween)
                + options.hexAfter
        }.joined(separator: "\n") + "\n"
    }
}
