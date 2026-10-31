import Foundation

/// The Apple II save formats MegaconvertGS added (its src/Save.s; the model in its
/// test/check_a2save.py, which both programs match byte for byte): HiRes and Double HiRes
/// (colour or black & white), LoRes and Double LoRes, plain or packed with PackBytes.
public enum AppleIISave {
    public enum Kind: String { case hgr, hgrbw, dhr, dhrbw, lores, dlores }

    static let palette = AppleIIFormats.palette
    static let hiResCandidates = [0, 15, 9, 6, 12, 3]
    static let toLoRes = [0, 1, 8, 9, 4, 5, 12, 13, 2, 3, 10, 11, 6, 7, 14, 15]
    static let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    @inline(__always) static func comps(_ c: Int) -> [Int] { [(c >> 8 & 15) * 17, (c >> 4 & 15) * 17, (c & 15) * 17] }

    /// The closest of the candidates (squared differences / 4; the first of equals).
    static func near(_ v: [Int], _ cands: [Int]) -> Int {
        var best = Int.max, k = 0
        for (i, n) in cands.enumerated() {
            let c = comps(Int(palette[n]))
            var d = 0
            for ch in 0..<3 { let x = abs(c[ch] - v[ch]) >> 2; d += x * x }
            if d < best { best = d; k = i }
        }
        return k
    }

    static func textOffset(_ t: Int) -> Int { (t & 7) * 128 + (t >> 3) * 40 }

    /// The screen (the picture's own size) as an Apple II screen: the whole screen (fit
    /// false) or as much as its proportions let it, centred; each place the average of the
    /// pixels it covers; then error diffusion (dither 0), a 4 x 4 Bayer pattern (1) or
    /// nothing (2), and the closest colour.
    public static func encode(_ screen: ScreenImage, _ kind: Kind, dither: Int = 0, fit: Bool = false) -> [UInt8] {
        let w = screen.width, h = screen.height
        let places = ["hgr": 140, "hgrbw": 280, "dhr": 140, "dhrbw": 560, "lores": 40, "dlores": 80][kind.rawValue]!
        let lo = kind == .lores || kind == .dlores
        let H = lo ? 48 : 192
        let bw = kind == .hgrbw || kind == .dhrbw
        let top = bw ? 2550 : 255, nch = bw ? 1 : 3
        var Wa = places, Ha = H, X0 = 0, Y0 = 0
        if fit {
            let p640 = screen.scbs.first.map { $0 & 0x80 != 0 } ?? screen.is640
            let A = 5 * w, B = (p640 ? 16 : 8) * h
            if B <= A { Ha = max((2 * H * B + A) / (2 * A), 1); Y0 = (H - Ha) / 2 }
            else { Wa = max((2 * places * A + B) / (2 * B), 1); X0 = (places - Wa) / 2 }
        }
        let rows = (0..<h).map { y in (0..<w).map { x in comps(Int(screen.colour(x, y)) & 0xFFF) } }
        let size = ["hgr": 8192, "hgrbw": 8192, "dhr": 16384, "dhrbw": 16384, "lores": 1024, "dlores": 2048][kind.rawValue]!
        var out = [UInt8](repeating: 0, count: size)
        var err = [[Int]](repeating: [Int](repeating: 0, count: places + 2), count: nch)
        for y in 0..<H {
            let yy = y - Y0
            var vals = [[Int]](), inside = [Bool]()
            var r0 = 0, r1 = 0
            if yy >= 0 && yy < Ha { r0 = yy * h / Ha; r1 = max((yy + 1) * h / Ha, r0 + 1) }
            for i in 0..<places {
                let ii = i - X0
                if yy >= 0 && yy < Ha && ii >= 0 && ii < Wa {
                    let x0 = ii * w / Wa, x1 = max((ii + 1) * w / Wa, x0 + 1)
                    var sum = [0, 0, 0], n = 0
                    for line in r0..<min(r1, h) { for x in x0..<min(x1, w) { let p = rows[line][x]; sum[0] += p[0]; sum[1] += p[1]; sum[2] += p[2]; n += 1 } }
                    vals.append(n > 0 ? sum.map { $0 / n } : [0, 0, 0]); inside.append(true)
                } else { vals.append([0, 0, 0]); inside.append(false) }
            }
            var nxt = [[Int]](repeating: [Int](repeating: 0, count: places + 2), count: nch)
            var vote = [Int](repeating: 0, count: 40), dotColour = [Int]()
            if kind == .hgr {
                for (i, c) in vals.enumerated() {
                    let k = hiResCandidates[near(c, hiResCandidates)]
                    vote[2 * i / 7] += (k == 12 || k == 3) ? 1 : (k == 9 || k == 6) ? -1 : 0
                }
                dotColour = (0..<280).map { d in vote[d / 7] > 0 ? (d % 2 == 0 ? 12 : 3) : (d % 2 == 0 ? 9 : 6) }
            }
            var dots = [Int](), carry = [Int](repeating: 0, count: nch)
            for (i, c) in vals.enumerated() {
                if !inside[i] {
                    for ch in 0..<nch { nxt[ch][i + 1] = 0; carry[ch] = 0 }
                    dots += bw || lo ? [0] : kind == .hgr ? [0, 0] : [0, 0, 0, 0]
                    continue
                }
                let pat = dither == 1 ? (2 * bayer[(y & 3) * 4 + (i & 3)] - 15) * (bw ? 80 : 5) : 0
                let base = bw ? [3 * c[0] + 6 * c[1] + c[2]] : c
                let v = base.enumerated().map { ch, x in min(max(x + err[ch][i + 1] + carry[ch] + pat, 0), top) }
                var p: [Int]
                if bw {
                    let on = v[0] >= 1275
                    p = [on ? 2550 : 0]; dots.append(on ? 1 : 0)
                } else {
                    let cands = kind == .hgr ? [0, 15, dotColour[2 * i], dotColour[2 * i + 1]] : Array(0..<16)
                    let k = near(v, cands)
                    p = comps(Int(palette[cands[k]]))
                    if lo { dots.append(cands[k]) }
                    else if kind == .hgr { dots += [[0, 0], [1, 1], [1, 0], [0, 1]][k] }
                    else { let n = cands[k]; dots += [n >> 3 & 1, n >> 2 & 1, n >> 1 & 1, n & 1] }
                }
                if dither != 0 { continue }
                for ch in 0..<nch {
                    let e = v[ch] - p[ch]
                    let e7 = (7 * e) >> 4, e3 = (3 * e) >> 4, e5 = (5 * e) >> 4
                    carry[ch] = e7
                    nxt[ch][i] += e3
                    nxt[ch][i + 1] += e5
                    nxt[ch][i + 2] += e - e7 - e3 - e5
                }
            }
            for ch in 0..<nch { nxt[ch][0] = 0; nxt[ch][places + 1] = 0 }
            err = nxt
            if lo {
                for (i, n) in dots.enumerated() {
                    var c = toLoRes[n]
                    var at = textOffset(y >> 1) + (kind == .dlores ? i >> 1 : i)
                    if kind == .dlores {
                        if i & 1 != 0 { at += 1024 } else { c = (c >> 1 | c << 3) & 15 }
                    }
                    out[at] |= UInt8(c << (y & 1 != 0 ? 4 : 0))
                }
                continue
            }
            for g in 0..<(dots.count / 7) {
                var byte = 0
                for i in 0..<7 { byte |= dots[7 * g + i] << i }
                if kind == .hgr && vote[g] > 0 { byte |= 0x80 }
                let row = AppleIIFormats.rowOffset(y)
                if kind == .hgr || kind == .hgrbw { out[row + g] = UInt8(byte) }
                else { out[row + g / 2 + (g & 1 != 0 ? 8192 : 0)] = UInt8(byte) }
            }
        }
        return out
    }
}
