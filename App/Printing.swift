import AppKit
import SCCore

/// Printing through the Mac's own print panel, plus the font list picture.
enum Printing {
    enum Job {
        /// `scale` nil = as large as fits; 1.0 = the width of the page.
        case picture(CGImage, scale: Double?, centered: Bool, caption: String?)
        case alignment
    }

    private final class PageView: NSView {
        let job: Job

        init(job: Job, frame: NSRect) {
            self.job = job
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            switch job {
            case .alignment:
                // An L in each corner of the printable area.
                context.setLineWidth(1)
                let arm: CGFloat = 36
                let b = bounds.insetBy(dx: 0.5, dy: 0.5)
                for (x, y, dx, dy) in [(b.minX, b.minY, arm, arm), (b.maxX, b.minY, -arm, arm),
                                       (b.minX, b.maxY, arm, -arm), (b.maxX, b.maxY, -arm, -arm)] {
                    context.move(to: CGPoint(x: x + dx, y: y))
                    context.addLine(to: CGPoint(x: x, y: y))
                    context.addLine(to: CGPoint(x: x, y: y + dy))
                }
                context.strokePath()
            case .picture(let image, let scale, let centered, let caption):
                let captionHeight: CGFloat = caption == nil ? 0 : 24
                let area = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - captionHeight)
                let shape = CGFloat(image.width) / CGFloat(image.height)
                var width = scale.map { area.width * CGFloat($0) } ?? min(area.width, area.height * shape)
                width = min(width, area.height * shape, area.width)
                let size = CGSize(width: width, height: width / shape)
                let origin = CGPoint(x: centered ? (area.width - size.width) / 2 : 0,
                                     y: centered ? (area.height - size.height) / 2 : 0)
                context.interpolationQuality = .none
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y + size.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(origin: .zero, size: size))
                context.restoreGState()
                if let caption {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    caption.draw(in: CGRect(x: 0, y: origin.y + size.height + 4, width: bounds.width, height: 20),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: style])
                }
            }
        }
    }

    static func run(_ job: Job) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        let printable = info.imageablePageBounds
        let view = PageView(job: job, frame: NSRect(origin: .zero, size: printable.size))
        NSPrintOperation(view: view, printInfo: info).run()
    }

    /// Family names, each drawn in its own font, black on white.
    static func fontListImage(_ families: [String]) -> TrueColorImage? {
        let width = 576, line = 25, height = max(line, families.count * line + 10)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (i, family) in families.enumerated() {
            let font = NSFont(name: family, size: 16)
                ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 16)
                ?? NSFont.systemFont(ofSize: 16)
            let y = CGFloat(height - 5 - (i + 1) * line)
            "\(family) 16".draw(at: NSPoint(x: 8, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = rep.cgImage else { return nil }
        return try? ModernImage.trueColor(from: image)
    }
}
