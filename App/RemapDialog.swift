import SCCore
import SwiftUI

struct RemapDialog: View {
    @ObservedObject var model: AppModel

    private func ratio(_ step: Int) -> String {
        let (n, d) = scaleSteps[step]
        return "\(n):\(d)"
    }

    var body: some View {
        let sizes = model.outputSize()
        let natural = model.trueColor.map { Remapper.naturalSize(of: $0, mode: model.settings.mode) } ?? (0, 0)
        let screenWidth = Double(model.screenWidth)
        GSDialog {
            HStack(alignment: .top, spacing: 10) {
                choicesColumn.frame(width: 180)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Button("Info on these options") {
                                model.overlay = .info("Remap options", """
                                    Graphic mode picks the IIgs screen mode of the result. Palette to use picks \
                                    its colors; Calculated finds the best ones for this picture.
                                    The two scroll bars set the scaling. The diagram shows the result against \
                                    a grid of screens: the curve is the 64K size limit, the thin outline is the \
                                    size you asked for and the thick one is what you get.
                                    Quick remap ignores every option and gives a one-screen preview.
                                    """)
                            }
                            .buttonStyle(GSButtonStyle())
                            Group {
                                if let s = model.statistics {
                                    Text("Distinct colors used: \(s.distinct)")
                                    Text("Distribution: \(model.distribution(s))")
                                } else {
                                    Text("Counting colors...")
                                }
                            }
                            .font(GS.font).foregroundColor(.black).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Other options").font(GS.font).foregroundColor(.black).underline()
                            GSCheckbox(title: "Integral scaling only", isOn: $model.settings.integral)
                            GSCheckbox(title: "Clip Horiz. before Vert.", isOn: $model.settings.clipHorizFirst)
                            GSCheckbox(title: "Clip to one screen", isOn: $model.settings.clipOneScreen)
                        }
                    }

                    // Scaling: text, scroll bars and the size diagram, laid out as in the original.
                    ZStack(alignment: .topLeading) {
                        Text("Vertical scaling: from \(natural.1) to \(sizes.wanted.1) (\(ratio(model.settings.vStep)))")
                            .font(GS.font).foregroundColor(.black).lineLimit(1)
                        Text("Horizontal: from \(natural.0) to \(sizes.wanted.0) (\(ratio(model.settings.hStep)))")
                            .font(GS.font).foregroundColor(.black).lineLimit(1)
                            .offset(x: 34, y: 18)
                        // Leader lines from each line of text to its scroll bar.
                        Path { p in
                            p.move(to: CGPoint(x: 10, y: 17))
                            p.addQuadCurve(to: CGPoint(x: Self.gridX - 16, y: Self.gridY + 8),
                                           control: CGPoint(x: 30, y: Self.gridY + 6))
                            p.move(to: CGPoint(x: 62, y: 35))
                            p.addQuadCurve(to: CGPoint(x: Self.gridX, y: Self.gridY - 9),
                                           control: CGPoint(x: 110, y: Self.gridY - 9))
                        }
                        .stroke(Color.black, lineWidth: 1)
                        VStack(spacing: 6) {
                            Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                            Button("Quick remap") { model.runRemap(quick: true) }.buttonStyle(GSButtonStyle())
                            Button("Normal remap") { model.runRemap(quick: false) }
                                .buttonStyle(GSButtonStyle(isDefault: true))
                                .keyboardShortcut(.defaultAction)
                        }
                        .frame(width: 130)
                        .offset(x: 0, y: 78)
                        ScaleBar(step: $model.settings.hStep, vertical: false)
                            .frame(width: SizeDiagram.size.width, height: 14)
                            .offset(x: Self.gridX, y: Self.gridY - 16)
                        ScaleBar(step: $model.settings.vStep, vertical: true)
                            .frame(width: 14, height: SizeDiagram.size.height)
                            .offset(x: Self.gridX - 16, y: Self.gridY)
                        SizeDiagram(wanted: CGSize(width: Double(sizes.wanted.0) / screenWidth,
                                                   height: Double(sizes.wanted.1) / 200),
                                    result: CGSize(width: Double(sizes.clipped.0) / screenWidth,
                                                   height: Double(sizes.clipped.1) / 200))
                            .offset(x: Self.gridX, y: Self.gridY)
                        if sizes.clipped != sizes.wanted {
                            Text("Clipped to \(sizes.clipped.0) x \(sizes.clipped.1)")
                                .font(GS.font).foregroundColor(.black).lineLimit(1)
                                .offset(x: 0, y: Self.gridY + SizeDiagram.size.height + 4)
                        }
                    }
                    .frame(width: 410, height: Self.gridY + SizeDiagram.size.height + 24, alignment: .topLeading)
                }
                .frame(width: 410, alignment: .leading)
            }
        }
        .fixedSize()
    }

    private static let gridX: CGFloat = 268, gridY: CGFloat = 76

    private var choicesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Graphic mode").font(GS.font).foregroundColor(.black).underline()
                ForEach(GraphicMode.allCases, id: \.rawValue) { mode in
                    GSRadio(title: mode.title, selected: model.settings.mode == mode) {
                        model.settings.mode = mode
                        model.normalise()
                        model.fitScaleToScreen()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Palette to use").font(GS.font).foregroundColor(.black).underline()
                ForEach(PaletteChoice.allCases, id: \.rawValue) { choice in
                    if choice == .other {
                        HStack(spacing: 4) {
                            GSRadio(title: "", selected: model.settings.palette == .other) {
                                model.settings.palette = .other
                                model.normalise()
                            }
                            Button("Get other...") { model.overlay = .getOther }.buttonStyle(GSButtonStyle())
                        }
                    } else {
                        GSRadio(title: choice.title, selected: model.settings.palette == choice,
                                enabled: model.prototype(for: choice) != nil) {
                            model.settings.palette = choice
                            model.normalise()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Rendering algorithm").font(GS.font).foregroundColor(.black).underline()
                ForEach(RenderAlgorithm.allCases, id: \.rawValue) { algorithm in
                    GSRadio(title: algorithm.title, selected: model.settings.algorithm == algorithm,
                            enabled: algorithm != .errorDiffusion || model.errorDiffusionAllowed) {
                        model.settings.algorithm = algorithm
                    }
                }
            }
        }
    }
}

/// A IIgs scroll bar used as a stepped control: one position per scaling ratio.
private struct ScaleBar: View {
    @Binding var step: Int
    let vertical: Bool
    private var last: Int { scaleSteps.count - 1 }

    private func arrow(_ forward: Bool) -> some View {
        Button { step = min(last, max(0, step + (forward ? 1 : -1))) } label: {
            Path { p in
                // A triangle pointing along the bar.
                let tip: CGFloat = forward ? 11 : 3, base: CGFloat = forward ? 3 : 11
                if vertical {
                    p.move(to: CGPoint(x: 7, y: tip)); p.addLine(to: CGPoint(x: 3, y: base)); p.addLine(to: CGPoint(x: 11, y: base))
                } else {
                    p.move(to: CGPoint(x: tip, y: 7)); p.addLine(to: CGPoint(x: base, y: 3)); p.addLine(to: CGPoint(x: base, y: 11))
                }
                p.closeSubpath()
            }
            .stroke(Color.black, lineWidth: 1)
            .frame(width: 14, height: 14)
            .background(Color.white)
            .border(Color.black, width: 1)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let track = GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let at = (length - 12) * CGFloat(step) / CGFloat(last)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(white: 0.75))
                Rectangle().fill(Color.white).border(Color.black, width: 1)
                    .frame(width: vertical ? geo.size.width : 12, height: vertical ? 12 : geo.size.height)
                    .offset(x: vertical ? 0 : at, y: vertical ? at : 0)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let f = min(1, max(0, (vertical ? value.location.y : value.location.x) / length))
                step = Int((f * CGFloat(last)).rounded())
            })
        }
        return Group {
            if vertical {
                VStack(spacing: 0) { arrow(false); track; arrow(true) }
            } else {
                HStack(spacing: 0) { arrow(false); track; arrow(true) }
            }
        }
        .border(Color.black, width: 1)
    }
}

/// The picture-size diagram: a purple grid two screens wide and two tall, with its lower
/// right corner cut away by the 64K limit (width x height can't pass about two screenfuls).
/// Sizes are given in screens. Thin green outline = the size asked for; thick = the result.
private struct SizeDiagram: View {
    let wanted: CGSize
    let result: CGSize
    static let cell = CGSize(width: 66, height: 42)
    static let size = CGSize(width: cell.width * 2, height: cell.height * 2)
    /// 65536 bytes over the 32000 of one screen.
    private static let limit = 2.048

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * Self.cell.width, y: y * Self.cell.height)
    }

    var body: some View {
        let purple = Color(red: 0.55, green: 0.15, blue: 0.75)
        let green = Color(red: 0.0, green: 0.6, blue: 0.1)
        let edge = Self.limit / 2
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: point(0, 2)); p.addLine(to: point(0, 0)); p.addLine(to: point(2, 0))
                p.addLine(to: point(2, edge))
                // The size limit: width x height = constant.
                var x = 2.0
                while x > edge {
                    p.addLine(to: point(x, Self.limit / x))
                    x -= 0.02
                }
                p.addLine(to: point(edge, 2)); p.addLine(to: point(0, 2))
                p.move(to: point(1, 0)); p.addLine(to: point(1, 2))
                p.move(to: point(0, 1)); p.addLine(to: point(2, 1))
            }
            .stroke(purple, style: StrokeStyle(lineWidth: 1, dash: [2, 1]))
            Text("1 Screen").font(GS.font).foregroundColor(.black).lineLimit(1)
                .frame(width: Self.cell.width, height: Self.cell.height)
            Rectangle().stroke(green, lineWidth: 1)
                .frame(width: max(2, wanted.width * Self.cell.width), height: max(2, wanted.height * Self.cell.height))
            Rectangle().stroke(green, lineWidth: 3)
                .frame(width: max(3, result.width * Self.cell.width), height: max(3, result.height * Self.cell.height))
        }
        .frame(width: Self.size.width + 2, height: Self.size.height + 2, alignment: .topLeading)
        .clipped()
    }
}

struct GetOtherDialog: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let mode = model.settings.mode
        let titles: [String] = mode == .multipalette
            ? MultipaletteOption.allCases.dropFirst().map(\.title)
            : PalettePrototype.others(mode).map(\.name)
        let heading = ["Other 320 mode palettes:", "Other 640 mode palettes:",
                       "Other 640 dither mode palettes:", "Other multipalette options:"][mode.rawValue]
        GSDialog {
            VStack(alignment: .leading, spacing: 5) {
                Text(heading).font(GS.font).foregroundColor(.black)
                ForEach(titles.indices, id: \.self) { i in
                    GSRadio(title: titles[i], selected: model.settings.other[mode.rawValue] == i) {
                        model.settings.other[mode.rawValue] = i
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = .remap }.buttonStyle(GSButtonStyle())
                    Button("OK") {
                        model.settings.palette = .other
                        model.normalise()
                        model.overlay = .remap
                    }
                    .buttonStyle(GSButtonStyle(isDefault: true))
                }
                .padding(.top, 6)
            }
            .frame(width: 330, alignment: .leading)
        }
        .fixedSize()
    }
}
