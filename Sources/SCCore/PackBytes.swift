import Foundation

/// Apple IIgs PackBytes run-length compression.
public enum PackBytes {
    /// Unpacks until the input runs out or `limit` bytes have been produced.
    public static func unpack(_ data: [UInt8], from start: Int = 0, limit: Int = Int.max) -> [UInt8] {
        var out: [UInt8] = []
        var i = start
        while i < data.count && out.count < limit {
            let flag = data[i]
            let n = Int(flag & 0x3F) + 1
            i += 1
            switch flag >> 6 {
            case 0:
                let end = min(i + n, data.count)
                out.append(contentsOf: data[i..<end])
                i = end
            case 1:
                guard i < data.count else { return out }
                out.append(contentsOf: repeatElement(data[i], count: n))
                i += 1
            case 2:
                guard i + 4 <= data.count else { return out }
                for _ in 0..<n { out.append(contentsOf: data[i..<(i + 4)]) }
                i += 4
            default:
                guard i < data.count else { return out }
                out.append(contentsOf: repeatElement(data[i], count: n * 4))
                i += 1
            }
        }
        if out.count > limit { out.removeLast(out.count - limit) }
        return out
    }

    /// Packs bytes using literal and single-byte repeat records.
    public static func pack(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var literal: [UInt8] = []
        func flush() {
            var i = 0
            while i < literal.count {
                let n = min(64, literal.count - i)
                out.append(UInt8(n - 1))
                out.append(contentsOf: literal[i..<(i + n)])
                i += n
            }
            literal.removeAll(keepingCapacity: true)
        }
        var i = 0
        while i < data.count {
            var run = 1
            while i + run < data.count && data[i + run] == data[i] && run < 256 { run += 1 }
            if run >= 3 {
                flush()
                var left = run
                while left >= 8 {
                    let quads = min(64, left / 4)
                    out.append(0xC0 | UInt8(quads - 1))
                    out.append(data[i])
                    left -= quads * 4
                }
                if left > 0 {
                    out.append(0x40 | UInt8(left - 1))
                    out.append(data[i])
                }
                i += run
            } else {
                literal.append(contentsOf: data[i..<(i + run)])
                i += run
            }
        }
        flush()
        return out
    }
}
