import SCCore
import SwiftUI

/// Help window: general topics, then a page per menu built from the items' own help lines.
struct HelpDialog: View {
    @ObservedObject var model: AppModel
    let menus: [(String, [MenuEntry])]

    private var topics: [(String, String)] {
        var pages: [(String, String)] = [
            ("How it works", """
                GS Remap keeps up to three images in memory: a screen image (what an Apple IIgs can \
                show), a true color image and a monochrome image.

                Pick a computer type and a format in the Load formats window, then Load. Formats \
                marked with * give a true color image and open the Remap dialog; the others give a \
                screen image directly.

                Pick a format in the Save formats window and Save to write the screen image.
                """),
            ("Remapping", """
                Remap turns a true color image into a screen image.

                Graphic mode sets the IIgs screen mode. Palette to use sets the colors: Calculated \
                finds the best ones for this picture, Default color keeps the standard palette. \
                Pattern dither mixes palette colors in small patterns; Error diffusion is offered \
                with grayscale and black & white palettes.

                Quick remap ignores the options and gives a one-screen preview.
                """),
        ]
        for (name, entries) in menus {
            let title = name == "\u{F8FF}" ? "Apple menu" : "\(name) menu"
            let text = entries.filter { $0.title != "-" }
                .map { "\($0.title)\n\($0.help)" }.joined(separator: "\n\n")
            pages.append((title, text))
        }
        return pages
    }

    /// Breaks text into lines of at most `width` characters, keeping blank lines.
    private func wrapped(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var line = ""
            for word in paragraph.split(separator: " ") {
                if !line.isEmpty && line.count + 1 + word.count > width {
                    lines.append(line)
                    line = ""
                }
                line += (line.isEmpty ? "" : " ") + word
            }
            lines.append(line)
        }
        return lines
    }

    var body: some View {
        let pages = topics
        let page = pages[min(model.helpTopic, pages.count - 1)]
        // Sized for the narrowest face; the other two fit with room to spare.
        let lines = wrapped(page.1, width: 46)
        GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text("GS Remap Help").font(GS.font).bold().foregroundColor(.black)
                HStack(alignment: .top, spacing: 8) {
                    GSList(items: pages.map(\.0), selection: $model.helpTopic, rows: 15)
                        .frame(width: 170)
                        .border(Color.black, width: 1)
                    GSList(items: lines, selection: .constant(-1), rows: 15)
                        .frame(width: 380)
                        .border(Color.black, width: 1)
                        .id(model.helpTopic)
                }
                HStack {
                    Spacer()
                    Button("Close") { model.overlay = nil }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .fixedSize()
    }
}

/// Examine file: hexadecimal and text side by side, or a chart of byte values.
struct ExamineDialog: View {
    @ObservedObject var model: AppModel
    private let rows = 14, perRow = 12

    private func line(_ row: Int) -> String {
        let bytes = model.examineBytes
        let start = (model.examineTop + row) * perRow
        guard start < bytes.count else { return "" }
        let slice = bytes[start..<min(bytes.count, start + perRow)]
        let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
        let text = String(slice.map { b -> Character in
            let c = b & 0x7F
            return c >= 0x20 && c < 0x7F ? Character(UnicodeScalar(c)) : "."
        })
        return String(format: "%06X  ", start) + hex.padding(toLength: perRow * 3, withPad: " ", startingAt: 0) + " " + text
    }

    var body: some View {
        let bytes = model.examineBytes
        let lastTop = max(0, (bytes.count + perRow - 1) / perRow - rows)
        GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.examineName): \(bytes.count) bytes").font(GS.font).bold().foregroundColor(.black).lineLimit(1)
                HStack(spacing: 14) {
                    GSRadio(title: "Data", selected: !model.examineHistogram) { model.examineHistogram = false }
                    GSRadio(title: "Histogram", selected: model.examineHistogram) { model.examineHistogram = true }
                }
                if model.examineHistogram {
                    histogram(bytes)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rows, id: \.self) { row in
                            Text(line(row)).font(GS.font).foregroundColor(.black).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: GS.rowHeight)
                        }
                    }
                    .padding(4)
                    .border(Color.black, width: 1)
                }
                HStack(spacing: 8) {
                    if !model.examineHistogram {
                        Button("Top") { model.examineTop = 0 }.buttonStyle(GSButtonStyle())
                        Button("Page up") { model.examineTop = max(0, model.examineTop - rows) }.buttonStyle(GSButtonStyle())
                        Button("Page down") { model.examineTop = min(lastTop, model.examineTop + rows) }.buttonStyle(GSButtonStyle())
                    }
                    Spacer()
                    Button("Close") { model.overlay = nil }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 560, alignment: .leading)
        }
        .fixedSize()
    }

    private func histogram(_ bytes: [UInt8]) -> some View {
        var counts = [Int](repeating: 0, count: 256)
        for b in bytes { counts[Int(b)] += 1 }
        let peak = max(1, counts.max() ?? 1)
        let top = counts.firstIndex(of: peak) ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<256, id: \.self) { v in
                    Rectangle().fill(Color.black)
                        .frame(width: 2, height: max(counts[v] > 0 ? 1 : 0, CGFloat(counts[v]) * 180 / CGFloat(peak)))
                }
            }
            .frame(width: 512, height: 184, alignment: .bottomLeading)
            .padding(4)
            .border(Color.black, width: 1)
            Text("Byte values $00 to $FF, left to right. Most common: $\(String(format: "%02X", top)), "
                 + "\(peak) times (\(bytes.isEmpty ? 0 : peak * 100 / bytes.count)% of the file).")
                .font(GS.font).foregroundColor(.black)
        }
    }
}

struct PrintOptionsDialog: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text("Print (enhanced)").font(GS.font).bold().foregroundColor(.black)
                GSField(label: "Width, % of the page (1-400):", text: $model.printScaleText, width: 60)
                GSCheckbox(title: "Center on the page", isOn: $model.printCentered)
                GSCheckbox(title: "Add caption", isOn: $model.printAddCaption)
                GSField(label: "Caption:", text: $model.printCaption, width: 250)
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button("Print...") { model.printEnhanced() }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 360, alignment: .leading)
        }
        .fixedSize()
    }
}

/// View half size (0), View X4 magnified (1) and View approximation (2). A click returns.
struct ViewerOverlay: View {
    @ObservedObject var model: AppModel
    let kind: Int
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        let image = kind == 2 ? model.trueColor.flatMap { ModernImage.cgImage($0) }
                              : model.screen.flatMap { ModernImage.cgImage($0) }
        let full = DesktopView.size
        ZStack {
            Color.black
            if let image {
                let picture = Image(decorative: image, scale: 1).interpolation(.none).resizable()
                switch kind {
                case 0:
                    picture.aspectRatio(contentMode: .fit).frame(width: full.width / 2, height: full.height / 2)
                case 1:
                    // Four times the full-screen size; the pointer's position picks the part shown.
                    picture.aspectRatio(contentMode: .fit)
                        .frame(width: full.width * 4, height: full.height * 4)
                        .offset(x: (0.5 - pointer.x) * full.width * 3, y: (0.5 - pointer.y) * full.height * 3)
                default:
                    picture.aspectRatio(contentMode: .fit)
                }
            }
        }
        .frame(width: full.width, height: full.height)
        .clipped()
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                pointer = CGPoint(x: location.x / full.width, y: location.y / full.height)
            }
        }
    }
}
