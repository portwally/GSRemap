import Foundation

/// A IIgs colour word, `$0RGB` with 4 bits per channel.
public typealias Color12 = UInt16

/// Colour arithmetic as SuperConvert does it (segment 2 of the original).
public enum ColorMath {
    /// 4-bit channel value → display intensity (original table at 02/8355).
    public static let intensity: [Int] = [0, 1, 5, 10, 18, 28, 41, 56, 73, 92, 113, 137, 163, 192, 222, 255]

    @inline(__always) public static func red(_ c: Color12) -> Int { Int(c >> 8) & 15 }
    @inline(__always) public static func green(_ c: Color12) -> Int { Int(c >> 4) & 15 }
    @inline(__always) public static func blue(_ c: Color12) -> Int { Int(c) & 15 }

    @inline(__always) public static func make(_ r: Int, _ g: Int, _ b: Int) -> Color12 {
        Color12((r & 15) << 8 | (g & 15) << 4 | (b & 15))
    }

    /// Weighted distance between two colours (02/6CFA).
    @inline(__always) public static func distance(_ x: Color12, _ y: Color12) -> Int {
        let a = 3 * (red(x) - red(y))
        let b = 4 * (green(x) - green(y))
        let c = 2 * (blue(x) - blue(y))
        return abs(a) + abs(b) + abs(c) + (abs(a + b + c) >> 2)
    }

    /// Brightness, 0…240 (02/6F9C).
    @inline(__always) public static func brightness(_ c: Color12) -> Int {
        5 * red(c) + 8 * green(c) + 3 * blue(c)
    }

    /// Grey level of 8-bit channels, as the scaler computes it.
    @inline(__always) public static func grey(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (5 * r + 8 * g + 3 * b) >> 4
    }

    public static func isGrey(_ c: Color12) -> Bool {
        red(c) == green(c) && green(c) == blue(c)
    }

    /// 8-bit RGB for display.
    @inline(__always) public static func rgb8(_ c: Color12) -> (UInt8, UInt8, UInt8) {
        (UInt8(red(c) * 17), UInt8(green(c) * 17), UInt8(blue(c) * 17))
    }
}
