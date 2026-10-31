import AppKit
import SCCore
import SwiftUI

// The image window of SuperConvert: an info bar with four pop-up menus (image type, zoom, tool, actions),
// a scrolling picture, a selection with marching ants, and the crop action.
// All positions inside the window are "image units": x counts 640-mode columns, y counts lines.
// On this desktop one unit is a point wide and a line is two points tall.

struct ImageSelection: Equatable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int
}

struct ImagePoint: Equatable {
    var x: Int
    var y: Int
}

enum ImagePopup { case type, zoom, tool, actions }

/// A rectangle in zoomed content coordinates.
struct ZRect {
    var top = 0, left = 0, bottom = 0, right = 0
}

/// The mouse gesture in progress: 1-9 move or resize (numeric keypad layout), 10 pixel peek, 11 new selection.
struct SelectionDrag {
    var code: Int
    var anchorV = 0, anchorH = 0
    var lastV = 0, lastH = 0
    var cur = ZRect()
    var location = CGPoint.zero
}

private var peekEverShown = false

@MainActor
extension AppModel {
    // MARK: Which image, how big

    /// 1 screen, 2 true color, 3 monochrome, 0 nothing: the same choice currentCGImage makes.
    var shownType: Int {
        if showMono || (screen == nil && trueColor == nil), mono != nil { return 3 }
        if showTrueColor || screen == nil, trueColor != nil { return 2 }
        return screen != nil ? 1 : 0
    }

    /// 0 = 320-sized pixels (two columns wide), 1 = 640-sized pixels (one column).
    func pixSize(_ type: Int) -> Int {
        switch type {
        case 2: return pixSizes[2] ?? (trueColor?.tallPixels == true ? 1 : 0)
        case 3: return pixSizes[3] ?? 1
        default: return 0
        }
    }

    var unitsSize: (w: Int, h: Int) {
        let t = shownType
        switch t {
        case 1: return screen.map { ($0.bytesPerRow * 4, $0.height) } ?? (0, 0)
        case 2: return trueColor.map { ($0.width * (pixSize(2) == 0 ? 2 : 1), $0.height) } ?? (0, 0)
        case 3: return mono.map { ($0.width * (pixSize(3) == 0 ? 2 : 1), $0.height) } ?? (0, 0)
        default: return (0, 0)
        }
    }

    /// The selection snaps to this many columns: a byte for a screen image, a pixel for the others.
    var stepX: Int { shownType == 1 ? 4 : (pixSize(shownType) == 0 ? 2 : 1) }

    /// Image units to pixels of the shown image.
    func pixelX(_ x: Int) -> Int {
        if shownType == 1 { return screen?.is640 == true ? x : x / 2 }
        return pixSize(shownType) == 0 ? x / 2 : x
    }

    /// The image's own size in pixels.
    var pixelSize: (w: Int, h: Int) {
        switch shownType {
        case 1: return screen.map { ($0.width, $0.height) } ?? (0, 0)
        case 2: return trueColor.map { ($0.width, $0.height) } ?? (0, 0)
        case 3: return mono.map { ($0.width, $0.height) } ?? (0, 0)
        default: return (0, 0)
        }
    }

    // MARK: Zoom (the four conversions of the original)

    func a2z(_ a: Int) -> Int { zoom >= 0 ? a << zoom : a >> -zoom }
    func a2zR(_ a: Int) -> Int {
        if zoom >= 0 { return a << zoom }
        var v = a
        for _ in 0..<(-zoom) { v = (v >> 1) + (v & 1) }
        return v
    }
    func z2a(_ a: Int) -> Int { zoom >= 0 ? a >> zoom : a << -zoom }
    func z2aR(_ a: Int) -> Int {
        if zoom < 0 { return a << -zoom }
        var v = a
        for _ in 0..<zoom { v = (v >> 1) + (v & 1) }
        return v
    }

    var contentSize: (w: Int, h: Int) { (a2zR(unitsSize.w), a2zR(unitsSize.h)) }

    // MARK: Bookkeeping

    func imageReplaced(_ type: Int) {
        imageVersion += 1
        selections[type] = nil
        pixSizes[type] = nil
        originX = 0
        originY = 0
        peekPoint = nil
        popup = nil
        drag = nil
        if type == 1 { zoom = 0 }
    }

    func setOrigin(_ x: Int, _ y: Int) {
        let c = contentSize
        let nx = max(0, min(x, c.w - Int(viewport.width)))
        let ny = max(0, min(y, c.h - Int(viewport.height / 2)))
        if nx != originX { originX = nx }
        if ny != originY { originY = ny }
    }

    func zoomAllowed(_ z: Int) -> Bool {
        if z <= 0 { return true }
        let m = max(unitsSize.w, unitsSize.h)
        return m < [5000, 2500, 1250][z - 1]
    }

    func setZoom(_ z: Int) {
        guard z != zoom, zoomAllowed(z) else { return }
        zoom = z
        setOrigin(originX, originY)
    }

    func setPixSize(_ size: Int) {
        let t = shownType
        guard t == 2 || t == 3, pixSize(t) != size else { return }
        if var s = selections[t] {
            if size == 1 { s.left /= 2; s.right /= 2 } else { s.left *= 2; s.right *= 2 }
            selections[t] = s
        }
        pixSizes[t] = size
        setOrigin(originX, originY)
    }

    func showType(_ t: Int) {
        guard t != shownType else { return }
        showMono = t == 3
        showTrueColor = t == 2
        peekPoint = nil
        originX = 0
        originY = 0
    }

    // MARK: The picture at image-unit resolution

    /// The shown image as one pixel per column and line, so any zoom is a plain scaling of it.
    func unitImage() -> CGImage? {
        let t = shownType
        guard t != 0 else { return nil }
        let key = [imageVersion, t, pixSize(t)]
        if let cache = unitCache, cache.key == key { return cache.image }
        let (w, h) = unitsSize
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        switch t {
        case 1:
            guard let s = screen else { return nil }
            for y in 0..<h {
                for x in 0..<s.width {
                    let (r, g, b) = ColorMath.rgb8(s.colour(x, y))
                    let u = s.is640 ? x : x * 2
                    for k in 0..<(s.is640 ? 1 : 2) {
                        let i = (y * w + u + k) * 4
                        rgba[i] = r; rgba[i + 1] = g; rgba[i + 2] = b
                    }
                }
            }
        case 2:
            guard let c = trueColor else { return nil }
            let twice = pixSize(2) == 0
            for y in 0..<h {
                for x in 0..<c.width {
                    let p = c.pixel(x, y)
                    for k in 0..<(twice ? 2 : 1) {
                        let i = (y * w + (twice ? x * 2 : x) + k) * 4
                        rgba[i] = p.r; rgba[i + 1] = p.g; rgba[i + 2] = p.b
                    }
                }
            }
        default:
            guard let m = mono else { return nil }
            let twice = pixSize(3) == 0
            for y in 0..<h {
                for x in 0..<m.width {
                    let v: UInt8 = m.pixels[y * m.width + x] == 0 ? 0 : 255
                    for k in 0..<(twice ? 2 : 1) {
                        let i = (y * w + (twice ? x * 2 : x) + k) * 4
                        rgba[i] = v; rgba[i + 1] = v; rgba[i + 2] = v
                    }
                }
            }
        }
        guard let image = ModernImage.cgImage(width: w, height: h, rgba: rgba) else { return nil }
        unitCache = (key, image)
        return image
    }

    /// The part of the picture inside the window and where it goes, in window points.
    func visiblePart(_ size: CGSize) -> (image: CGImage, frame: CGRect)? {
        guard let full = unitImage() else { return nil }
        let (w, h) = unitsSize
        let x0 = max(0, z2a(originX)), x1 = min(w, z2aR(originX + Int(size.width) + 1))
        let y0 = max(0, z2a(originY)), y1 = min(h, z2aR(originY + Int(size.height / 2) + 1))
        guard x1 > x0, y1 > y0,
              let part = full.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
        let frame = CGRect(x: a2z(x0) - originX, y: (a2z(y0) - originY) * 2,
                           width: a2zR(x1) - a2z(x0), height: (a2zR(y1) - a2z(y0)) * 2)
        return (part, frame)
    }

    // MARK: Selection

    func zoomRect(_ s: ImageSelection) -> ZRect {
        ZRect(top: a2z(s.top), left: a2z(s.left), bottom: a2zR(s.bottom), right: a2zR(s.right))
    }

    /// The selection frame in window points.
    func selectionFrame() -> CGRect? {
        guard let s = selections[shownType] else { return nil }
        let r = zoomRect(s)
        return CGRect(x: r.left - originX, y: (r.top - originY) * 2,
                      width: r.right - r.left, height: (r.bottom - r.top) * 2)
    }

    private func storeSelection(_ r: ZRect) {
        let (w, h) = unitsSize
        let top = z2a(r.top), left = z2a(r.left)
        let bottom = min(z2aR(r.bottom), h), right = min(z2aR(r.right), w)
        let t = shownType
        selections[t] = bottom > top && right > left ? ImageSelection(top: top, left: left, bottom: bottom, right: right) : nil
    }

    private func snap(_ v: Int, _ step: Int) -> Int {
        let s = zoom > 0 ? step << zoom : 1
        let q = v + s / 2
        return (q >= 0 ? q / s : -((-q + s - 1) / s)) * s
    }

    private func limit(_ v: Int, _ end: Int, _ step: Int) -> Int {
        if v < 0 { return 0 }
        let s = zoom > 0 ? step << zoom : 1
        return v >= end ? end / s * s : v
    }

    private func hitCode(_ h: Int, _ v: Int, _ r: ZRect, option: Bool) -> Int {
        var hz = 0, vz = 0
        if option {
            hz = h <= (r.left + r.right) / 2 ? 1 : 3
            vz = v <= (r.top + r.bottom) / 2 ? 4 : 12
        } else {
            if (-6..<6).contains(h - r.left) { hz = 1 } else if (-6..<6).contains(h - r.right) { hz = 3 }
            else if h >= r.left && h <= r.right { hz = 2 }
            if (-3..<3).contains(v - r.top) { vz = 4 } else if (-3..<3).contains(v - r.bottom) { vz = 12 }
            else if v >= r.top && v <= r.bottom { vz = 8 }
        }
        guard hz != 0, vz != 0 else { return 11 }
        let table: [Int: [Int]] = [4: [0, 7, 8, 9], 8: [0, 4, 5, 6], 12: [0, 1, 2, 3]]
        return table[vz]![hz]
    }

    /// What the pointer would do at this window position: the original's cursor codes.
    func cursorCode(_ p: CGPoint) -> Int {
        if tool == 2 { return 10 }
        guard let s = selections[shownType] else { return 11 }
        let h = originX + Int(p.x.rounded(.down)), v = originY + Int((p.y / 2).rounded(.down))
        return hitCode(h, v, zoomRect(s), option: NSEvent.modifierFlags.contains(.option))
    }

    func cursor(_ code: Int) -> NSCursor {
        switch code {
        case 2, 8: return .resizeUpDown
        case 4, 6: return .resizeLeftRight
        case 5: return .openHand
        default: return .crosshair
        }
    }

    // MARK: Mouse

    private func zoomPoint(_ p: CGPoint) -> (h: Int, v: Int) {
        (originX + Int(p.x.rounded(.down)), originY + Int((p.y / 2).rounded(.down)))
    }

    func imageDown(_ p: CGPoint) {
        popup = nil
        let t = shownType
        guard t != 0 else { return }
        var (h, v) = zoomPoint(p)
        if tool == 2 {
            drag = SelectionDrag(code: 10, location: p)
            peekAt(h, v)
            return
        }
        let sel = selections[t].map(zoomRect)
        let code = sel.map { hitCode(h, v, $0, option: NSEvent.modifierFlags.contains(.option)) } ?? 11
        let now = Date()
        let isDouble = now.timeIntervalSince(lastDownTime) < 0.4
        lastDownTime = now
        if isDouble && code == 11 {
            let (w, hh) = unitsSize
            selections[t] = ImageSelection(top: 0, left: 0, bottom: hh, right: w)
            drag = SelectionDrag(code: 0)
            return
        }
        h = snap(h, stepX)
        v = snap(v, 1)
        var d = SelectionDrag(code: code, location: p)
        let cur = sel ?? ZRect()
        d.anchorV = v
        d.anchorH = h
        switch code {
        case 1: d.anchorV = cur.top; d.anchorH = cur.right
        case 3: d.anchorV = cur.top; d.anchorH = cur.left
        case 7: d.anchorV = cur.bottom; d.anchorH = cur.right
        case 9: d.anchorV = cur.bottom; d.anchorH = cur.left
        case 2: d.anchorV = cur.top
        case 8: d.anchorV = cur.bottom
        case 4: d.anchorH = cur.right
        case 6: d.anchorH = cur.left
        case 5: d.lastV = v; d.lastH = h
        default: break
        }
        if code == 11 { selections[t] = nil }
        d.cur = cur
        drag = d
    }

    func imageDragged(_ p: CGPoint) {
        guard var d = drag, d.code != 0 else { return }
        d.location = p
        var ox = originX, oy = originY
        if p.x < 0 { ox -= 16 } else if p.x >= viewport.width { ox += 16 }
        if p.y < 0 { oy -= 8 } else if p.y >= viewport.height { oy += 8 }
        setOrigin(ox, oy)
        let (h, v) = zoomPoint(p)
        if d.code == 10 {
            drag = d
            peekAt(h, v)
            return
        }
        let c = contentSize
        let ph = limit(snap(h, stepX), c.w, stepX), pv = limit(snap(v, 1), c.h, 1)
        var n = d.cur
        switch d.code {
        case 5:
            let dv = pv - d.lastV, dh = ph - d.lastH
            d.lastV = pv
            d.lastH = ph
            n.top += dv; n.bottom += dv; n.left += dh; n.right += dh
            if n.left < 0 { n.right -= n.left; n.left = 0 }
            if n.right > c.w { n.left -= n.right - c.w; n.right = c.w }
            if n.top < 0 { n.bottom -= n.top; n.top = 0 }
            if n.bottom > c.h { n.top -= n.bottom - c.h; n.bottom = c.h }
            n.left = max(0, n.left)
            n.top = max(0, n.top)
        case 2, 8:
            n.top = min(d.anchorV, pv); n.bottom = max(d.anchorV, pv)
        case 4, 6:
            n.left = min(d.anchorH, ph); n.right = max(d.anchorH, ph)
        default:
            n.top = min(d.anchorV, pv); n.bottom = max(d.anchorV, pv)
            n.left = min(d.anchorH, ph); n.right = max(d.anchorH, ph)
        }
        d.cur = n
        drag = d
        storeSelection(n)
    }

    func imageUp() { drag = nil }

    /// While the button is held outside the window the picture keeps scrolling.
    func imageTick() {
        guard let d = drag, d.code != 0 else { return }
        let p = d.location
        if p.x < 0 || p.y < 0 || p.x >= viewport.width || p.y >= viewport.height { imageDragged(p) }
    }

    private func peekAt(_ h: Int, _ v: Int) {
        let (w, hh) = unitsSize
        guard w > 0, hh > 0 else { return }
        peekPoint = ImagePoint(x: min(max(z2a(h), 0), w - 1), y: min(max(z2a(v), 0), hh - 1))
        peekEverShown = true
    }

    // MARK: Info bar text

    /// The info bar text, longest first; the bar shows the first that fits.
    func infoVariants() -> [String] {
        let t = shownType
        guard t != 0 else { return [""] }
        if tool == 2 { return peekVariants(t) }
        let kind = ["", "Screen image", "True color image", "Monochrome image"][t]
        if let s = selections[t] {
            let w = pixelX(s.right) - pixelX(s.left), h = s.bottom - s.top
            return ["Selection: \(w) x \(h)   (\(s.top), \(pixelX(s.left)), \(s.bottom), \(pixelX(s.right)))",
                    "Selection: \(w) x \(h)", "\(w) x \(h)"]
        }
        let (w, h) = pixelSize
        return ["\(kind): \(w) x \(h)", "Image: \(w) x \(h)", "\(w) x \(h)"]
    }

    private func peekVariants(_ t: Int) -> [String] {
        guard let pt = peekPoint else {
            return peekEverShown ? [" "] : ["Click in image to view pixel values", "Click in image"]
        }
        let (pw, ph) = pixelSize
        let x = min(max(pixelX(pt.x), 0), max(pw - 1, 0)), y = min(max(pt.y, 0), max(ph - 1, 0))
        let lead = "\(x),\(y)    "
        switch t {
        case 1:
            guard let s = screen else { return [""] }
            let pal = s.paletteIndex(line: y)
            let v = Int(s.pixels[y * s.width + x])
            let idx = s.is640 ? "\(v)\(x & 1 == 0 ? "e" : "o")" : "\(v)"
            let col = String(format: "$%03X", s.colour(x, y))
            return [lead + "Palette \(pal)  Index \(idx)  Color \(col)", lead + "P\(pal)  I\(idx)  \(col)", "P\(pal)  I\(idx)  \(col)"]
        case 2:
            guard let c = trueColor else { return [""] }
            let p = c.pixel(x, y)
            if isGreyImage {
                return [lead + "Gray \(p.r)", lead + "Gray \(p.r)", "Gray \(p.r)"]
            }
            let r = Int(p.r) >> 3, g = Int(p.g) >> 3, b = Int(p.b) >> 3
            return [lead + "Red \(r)  Green \(g)  Blue \(b)", lead + "R\(r)  G\(g)  B\(b)", "R\(r)  G\(g)  B\(b)"]
        default:
            guard let m = mono else { return [""] }
            let word = m.pixels[y * m.width + x] == 0 ? "Black" : "White"
            return [lead + word, lead + word, word]
        }
    }

    private var isGreyImage: Bool {
        if let cache = greyCache, cache.version == imageVersion { return cache.grey }
        let grey = trueColor?.colourStatistics().isGrey ?? false
        greyCache = (imageVersion, grey)
        return grey
    }

    // MARK: Actions

    var hasSelection: Bool { selections[shownType] != nil }

    func cropToSelection() {
        let t = shownType
        guard let s = selections[t] else { return }
        let left = pixelX(s.left), right = pixelX(s.right)
        switch t {
        case 1:
            guard let screen else { return }
            self.screen = screen.cropped(left: left, top: s.top, right: right, bottom: s.bottom)
            showMono = false
            showTrueColor = false
            overlay = .fullScreen
        case 2:
            guard let trueColor else { return }
            self.trueColor = trueColor.cropped(left: left, top: s.top, right: right, bottom: s.bottom)
            statistics = nil
        default:
            guard let mono else { return }
            self.mono = mono.cropped(left: left, top: s.top, right: right, bottom: s.bottom)
        }
    }

    func discardThisImageType() {
        switch shownType {
        case 1: screen = nil
        case 2: trueColor = nil
        default: mono = nil
        }
        afterDiscard()
    }

    func discardOtherImageTypes() {
        let keep = shownType
        if keep != 1 { screen = nil }
        if keep != 2 { trueColor = nil }
        if keep != 3 { mono = nil }
        afterDiscard()
    }

    private func afterDiscard() {
        guard hasImage else {
            closeImage()
            return
        }
        showTrueColor = screen == nil && trueColor != nil
        showMono = screen == nil && trueColor == nil
    }
}

// MARK: - Views

/// An icon from IIgsIcons: one character per 640-mode pixel, two points tall.
struct PixelIcon: View {
    let rows: [String]
    var body: some View {
        let width = rows.first?.count ?? 0
        return Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() {
                    let color: Color
                    switch c {
                    case "#": color = .black
                    case ".": color = .white
                    case "1": color = x & 1 == 0 ? Color(red: 0.87, green: 0, blue: 0) : Color(red: 0, green: 0, blue: 0.87)
                    case "2": color = x & 1 == 0 ? Color(red: 0, green: 0.8, blue: 0) : Color(red: 0.93, green: 0.93, blue: 0)
                    default: continue
                    }
                    context.fill(Path(CGRect(x: x, y: y * 2, width: 1, height: 2)), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(width), height: CGFloat(rows.count * 2))
    }
}

/// The open pop-up menu and the click catcher behind it; an overlay of the whole image window.
struct ImagePopupLayer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let popup = model.popup {
                // A click anywhere else closes the menu; the menu sits where the original's pop-ups open.
                Color.clear
                    .frame(width: 4000, height: 4000)
                    .contentShape(Rectangle())
                    .onTapGesture { model.popup = nil }
                    .offset(x: -2000, y: -2000)
                ImagePopupMenu(model: model, popup: popup)
                    .offset(x: [ImagePopup.type: 0, .zoom: 40, .tool: 80, .actions: 120][popup]!,
                            y: popup == .actions ? ImageInfoBar.height + 1 : -1)
            }
        }
    }
}

struct ImageInfoBar: View {
    @ObservedObject var model: AppModel
    static let height: CGFloat = 24

    var body: some View {
        let type = model.shownType
        let typeIcon = type == 2 ? IIgsIcons.trueColor : type == 3 ? IIgsIcons.mono : IIgsIcons.screen
        let zoomIcon = model.zoom == 0 ? IIgsIcons.zoomActual : model.zoom < 0 ? IIgsIcons.zoomShrunk : IIgsIcons.zoomLarge
        let toolIcon = model.tool == 2 ? IIgsIcons.peek : IIgsIcons.select
        let variants = model.infoVariants()
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.white
                PixelIcon(rows: typeIcon).offset(x: 2, y: 2)
                PixelIcon(rows: IIgsIcons.arrow).offset(x: 20, y: 2)
                PixelIcon(rows: zoomIcon).offset(x: 42, y: 4)
                PixelIcon(rows: IIgsIcons.arrow).offset(x: 60, y: 2)
                PixelIcon(rows: toolIcon).offset(x: 82, y: 4)
                PixelIcon(rows: IIgsIcons.arrow).offset(x: 100, y: 2)
                PixelIcon(rows: IIgsIcons.actionArrow).offset(x: 122, y: 2)
                ViewThatFits(in: .horizontal) {
                    ForEach(variants.indices, id: \.self) { i in
                        Text(variants[i]).font(GS.font).foregroundColor(.black).lineLimit(1).fixedSize()
                    }
                }
                .frame(width: max(0, geo.size.width - 146), height: ImageInfoBar.height, alignment: .leading)
                .clipped()
                .offset(x: 144)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                guard model.hasImage else { return }
                let which: ImagePopup? = tap.location.x < 40 ? .type : tap.location.x < 80 ? .zoom
                    : tap.location.x < 120 ? .tool : tap.location.x < 140 ? .actions : nil
                model.popup = which == model.popup ? nil : which
            })
        }
        .frame(height: ImageInfoBar.height)
    }
}

/// The picture, its selection and the two scroll bars.
struct ImageContent: View {
    @ObservedObject var model: AppModel
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let content = model.contentSize
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                viewport
                Rectangle().fill(Color.black).frame(height: 1)
                GSScrollBar(vertical: false, value: model.originX, maxValue: max(0, content.w - Int(model.viewport.width)),
                            page: Int(model.viewport.width), content: content.w, step: 8) {
                    model.setOrigin($0, model.originY)
                }
                .frame(height: 16)
            }
            Rectangle().fill(Color.black).frame(width: 1)
            VStack(spacing: 0) {
                GSScrollBar(vertical: true, value: model.originY, maxValue: max(0, content.h - Int(model.viewport.height / 2)),
                            page: Int(model.viewport.height / 2), content: content.h, step: 4) {
                    model.setOrigin(model.originX, $0)
                }
                Rectangle().fill(Color.black).frame(height: 1)
                Rectangle().fill(Color.white).frame(width: 16, height: 16)
            }
            .frame(width: 16)
        }
    }

    private var viewport: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(white: 0.72)
                if let part = model.visiblePart(geo.size) {
                    Image(decorative: part.image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: part.frame.width, height: part.frame.height)
                        .offset(x: part.frame.minX, y: part.frame.minY)
                }
                if model.selections[model.shownType] != nil {
                    TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                        let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 10) % 4
                        Canvas { context, _ in
                            guard let frame = model.selectionFrame() else { return }
                            let path = Path(frame.insetBy(dx: 1, dy: 1))
                            context.stroke(path, with: .color(.black), lineWidth: 2)
                            context.stroke(path, with: .color(.white),
                                           style: StrokeStyle(lineWidth: 2, dash: [2, 6], dashPhase: CGFloat(phase * 2)))
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if model.drag == nil {
                        model.viewport = geo.size
                        model.imageDown(value.startLocation)
                    }
                    model.imageDragged(value.location)
                }
                .onEnded { _ in model.imageUp() })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): model.cursor(model.cursorCode(p)).set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .onAppear { model.viewport = geo.size }
            .onChange(of: geo.size) { model.viewport = $0 }
            .onReceive(ticker) { _ in model.imageTick() }
        }
    }
}

/// A IIgs scroll bar: arrows at both ends, a gray track and a white thumb.
struct GSScrollBar: View {
    let vertical: Bool
    let value: Int
    let maxValue: Int
    let page: Int
    let content: Int
    let step: Int
    let set: (Int) -> Void
    @State private var grab: CGFloat?

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            arrow(0) { set(value - step) }
            separator
            track
            separator
            arrow(vertical ? 2 : 1) { set(value + step) }
        }
    }

    @ViewBuilder private var separator: some View {
        if vertical { Rectangle().fill(Color.black).frame(height: 1) } else { Rectangle().fill(Color.black).frame(width: 1) }
    }

    /// 0 = up or left, 1 = right, 2 = down.
    private func arrow(_ direction: Int, _ action: @escaping () -> Void) -> some View {
        let turns = vertical ? (direction == 2 ? 180.0 : 0) : (direction == 1 ? 90 : -90)
        return Button(action: action) {
            ZStack {
                Color.white
                Path { p in
                    p.move(to: CGPoint(x: 8, y: 3))
                    p.addLine(to: CGPoint(x: 2, y: 9))
                    p.addLine(to: CGPoint(x: 5, y: 9))
                    p.addLine(to: CGPoint(x: 5, y: 13))
                    p.addLine(to: CGPoint(x: 11, y: 13))
                    p.addLine(to: CGPoint(x: 11, y: 9))
                    p.addLine(to: CGPoint(x: 14, y: 9))
                    p.closeSubpath()
                }
                .stroke(Color.black, lineWidth: 1)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(turns))
            }
            .frame(width: vertical ? nil : 16, height: vertical ? 16 : nil)
        }
        .buttonStyle(.plain)
    }

    private var track: some View {
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let scrollable = maxValue > 0
            let thumb = scrollable ? max(12, length * CGFloat(page) / CGFloat(max(content, 1))) : 0
            let room = max(0, length - thumb)
            let position = scrollable ? room * CGFloat(value) / CGFloat(maxValue) : 0
            ZStack(alignment: .topLeading) {
                Rectangle().fill(scrollable ? Color(white: 0.75) : Color.white)
                if scrollable {
                    Rectangle()
                        .fill(Color.white)
                        .border(Color.black, width: 1)
                        .frame(width: vertical ? geo.size.width : thumb, height: vertical ? thumb : geo.size.height)
                        .offset(x: vertical ? 0 : position, y: vertical ? position : 0)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard scrollable else { return }
                    let start = vertical ? drag.startLocation.y : drag.startLocation.x
                    let now = vertical ? drag.location.y : drag.location.x
                    if grab == nil {
                        if start >= position && start <= position + thumb {
                            grab = start - position
                        } else {
                            set(value + (start < position ? -page : page))
                            grab = -1
                            return
                        }
                    }
                    if let grab, grab >= 0, room > 0 { set(Int(((now - grab) / room * CGFloat(maxValue)).rounded())) }
                }
                .onEnded { _ in grab = nil })
        }
    }
}

/// The four pop-up menus of the info bar.
struct ImagePopupMenu: View {
    @ObservedObject var model: AppModel
    let popup: ImagePopup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch popup {
            case .type: typeRows
            case .zoom: zoomRows
            case .tool: toolRows
            case .actions: actionRows
            }
        }
        .padding(.vertical, 2)
        .fixedSize()
        .background(Color.white)
        .border(Color.black, width: 1)
        .background(Color.black.offset(x: 2, y: 2))
    }

    private func pick(_ action: @escaping () -> Void) -> () -> Void {
        { model.popup = nil; action() }
    }

    @ViewBuilder private var typeRows: some View {
        let t = model.shownType
        PopRow(icon: IIgsIcons.screen, title: "Screen image", checked: false, enabled: model.screen != nil,
               action: pick { model.showType(1) })
        PopRow(icon: IIgsIcons.trueColor, title: "True color image", checked: false, enabled: model.trueColor != nil,
               action: pick { model.showType(2) })
        PopRow(icon: IIgsIcons.mono, title: "Monochrome image", checked: false, enabled: model.mono != nil,
               action: pick { model.showType(3) })
        Rectangle().fill(Color.gray).frame(height: 1).padding(.vertical, 3)
        PopRow(icon: IIgsIcons.pixels320, title: "320-sized pixels", checked: t > 1 && model.pixSize(t) == 0, enabled: t > 1,
               action: pick { model.setPixSize(0) })
        PopRow(icon: IIgsIcons.pixels640, title: "640-sized pixels", checked: t > 1 && model.pixSize(t) == 1, enabled: t > 1,
               action: pick { model.setPixSize(1) })
    }

    @ViewBuilder private var zoomRows: some View {
        let names = ["1/8 shrink", "1/4 shrink", "1/2 shrink", "Actual size", "2X zoom", "4X zoom", "8X zoom"]
        ForEach(0..<7, id: \.self) { i in
            let z = i - 3
            PopRow(icon: nil, title: names[i], checked: model.zoom == z, enabled: model.zoomAllowed(z),
                   action: pick { model.setZoom(z) })
        }
    }

    @ViewBuilder private var toolRows: some View {
        PopRow(icon: IIgsIcons.select, title: "Selection mode", checked: model.tool == 1, enabled: true,
               action: pick { model.tool = 1 })
        PopRow(icon: IIgsIcons.peek, title: "Pixel peek mode", checked: model.tool == 2, enabled: true,
               action: pick { model.tool = 2 })
    }

    @ViewBuilder private var actionRows: some View {
        PopRow(icon: nil, title: "Crop to selection", checked: false, enabled: model.hasSelection,
               action: pick { model.cropToSelection() })
        PopRow(icon: nil, title: "Discard this image type", checked: false, enabled: true,
               action: pick { model.discardThisImageType() })
        PopRow(icon: nil, title: "Discard other image types", checked: false, enabled: true,
               action: pick { model.discardOtherImageTypes() })
    }
}

private struct PopRow: View {
    let icon: [String]?
    let title: String
    let checked: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let lit = hovering && enabled
        HStack(spacing: 4) {
            Text(checked ? "\u{2713}" : " ").font(.system(size: 12)).frame(width: 12)
            if let icon { PixelIcon(rows: icon).frame(width: 16) }
            Text(title).font(GS.font)
        }
        .foregroundColor(lit ? .white : (enabled ? .black : .gray))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 19)
        .background(lit ? Color.black : Color.white)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if enabled { action() } }
    }
}
