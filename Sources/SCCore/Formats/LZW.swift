import Foundation

/// GIF-style LZW as DreamGrafix uses it (original decoder at 07/0000):
/// 9 to 12 bit codes packed low bit first, clear code $100, end code $101.
public enum LZW {
    public static func decode(_ data: [UInt8], limit: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(limit)
        var prefix = [Int](repeating: 0, count: 4096)
        var suffix = [UInt8](repeating: 0, count: 4096)
        var stack: [UInt8] = []
        var width = 9, top = 0x200, next = 0x102
        var bit = 0
        var previous = -1
        var first: UInt8 = 0

        func read() -> Int? {
            let byte = bit >> 3
            guard byte < data.count else { return nil }
            var v = Int(data[byte])
            if byte + 1 < data.count { v |= Int(data[byte + 1]) << 8 }
            if byte + 2 < data.count { v |= Int(data[byte + 2]) << 16 }
            return (v >> (bit & 7)) & ((1 << width) - 1)
        }

        while out.count < limit, let code = read() {
            bit += width
            if code == 0x101 { break }
            if code == 0x100 {
                width = 9
                top = 0x200
                next = 0x102
                previous = -1
                continue
            }
            if previous < 0 {
                first = UInt8(truncatingIfNeeded: code)
                out.append(first)
                previous = code
                continue
            }
            var walk = code
            if code >= next {
                stack.append(first)
                walk = previous
            }
            while walk >= 0x100 {
                stack.append(suffix[walk])
                walk = prefix[walk]
            }
            first = UInt8(walk)
            out.append(first)
            while let b = stack.popLast() { out.append(b) }
            if next < 4096 {
                suffix[next] = first
                prefix[next] = previous
                next += 1
                if next >= top && width < 12 {
                    width += 1
                    top <<= 1
                }
            }
            previous = code
        }
        if out.count > limit { out.removeLast(out.count - limit) }
        return out
    }
}
