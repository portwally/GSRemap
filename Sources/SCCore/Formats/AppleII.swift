import Foundation

/// Apple II HiRes and Double HiRes screens. Both load as 320-mode screen images
/// (280 x 192) in colour; Double HiRes can also load as 560 x 192 black & white.
public enum AppleIIFormats {
    /// Palette in Double HiRes bit-pattern order (the original's "Apple II LoRes/Double HiRes colors").
    public static let palette: [Color12] = [
        0x000, 0xD03, 0x852, 0xF60, 0x070, 0x555, 0x0D0, 0xFF0,
        0x009, 0xD0D, 0xAAA, 0xF98, 0x22F, 0x6AF, 0x0F9, 0xFFF,
    ]
    static let orange: UInt8 = 3, green: UInt8 = 6, violet: UInt8 = 9, blue: UInt8 = 12, white: UInt8 = 15

    /// Offset of a screen line within an 8192-byte HiRes page.
    static func rowOffset(_ y: Int) -> Int {
        (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28
    }

    public static func loadHiRes(_ d: [UInt8]) throws -> ScreenImage {
        guard d.count >= 8184 else { throw FormatError.notThisFormat("an Apple II HiRes screen") }
        var screen = ScreenImage(width: 280, height: 192, is640: false, palettes: [palette])
        for y in 0..<192 {
            let base = rowOffset(y)
            var on = [Bool](repeating: false, count: 280)
            var shifted = [Bool](repeating: false, count: 280)
            for col in 0..<40 where base + col < d.count {
                let byte = d[base + col]
                for bit in 0..<7 {
                    on[col * 7 + bit] = byte & (1 << UInt8(bit)) != 0
                    shifted[col * 7 + bit] = byte & 0x80 != 0
                }
            }
            func tint(_ x: Int) -> UInt8 {
                if x & 1 == 0 { return shifted[x] ? blue : violet }
                return shifted[x] ? orange : green
            }
            for x in 0..<280 {
                let left = x > 0 && on[x - 1], right = x < 279 && on[x + 1]
                var value: UInt8 = 0
                if on[x] {
                    value = left || right ? white : tint(x)
                } else if left && right {
                    value = tint(x - 1)
                }
                screen.pixels[y * 280 + x] = value
            }
        }
        return screen
    }

    /// 16384 bytes: auxiliary memory page first, then main memory.
    public static func loadDoubleHiRes(_ d: [UInt8], colour: Bool) throws -> ScreenImage {
        guard d.count >= 16376 else { throw FormatError.notThisFormat("an Apple II Double HiRes screen") }
        var screen = colour
            ? ScreenImage(width: 280, height: 192, is640: false, palettes: [palette])
            : ScreenImage(width: 560, height: 192, is640: true,
                          palettes: [[0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF,
                                      0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF, 0x000, 0xFFF]])
        for y in 0..<192 {
            let base = rowOffset(y)
            var bits = [UInt8](repeating: 0, count: 560)
            for col in 0..<40 {
                let aux = d[base + col]
                let main = base + col + 8192 < d.count ? d[base + col + 8192] : 0
                for bit in 0..<7 {
                    bits[col * 14 + bit] = (aux >> UInt8(bit)) & 1
                    bits[col * 14 + 7 + bit] = (main >> UInt8(bit)) & 1
                }
            }
            if colour {
                for x in 0..<140 {
                    // The first dot on screen is the high bit of the colour number.
                    let p = bits[x * 4] << 3 | bits[x * 4 + 1] << 2 | bits[x * 4 + 2] << 1 | bits[x * 4 + 3]
                    screen.pixels[y * 280 + x * 2] = p
                    screen.pixels[y * 280 + x * 2 + 1] = p
                }
            } else {
                for x in 0..<560 { screen.pixels[y * 560 + x] = bits[x] }
            }
        }
        return screen
    }
}
