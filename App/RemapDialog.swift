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
        GSDialog {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 6) {
                    GSGroup(title: "Graphic mode") {
                        ForEach(GraphicMode.allCases, id: \.rawValue) { mode in
                            GSRadio(title: mode.title, selected: model.settings.mode == mode) {
                                model.settings.mode = mode
                                model.normalise()
                                model.fitScaleToScreen()
                            }
                        }
                    }
                    GSGroup(title: "Palette to use") {
                        ForEach(PaletteChoice.allCases, id: \.rawValue) { choice in
                            if choice == .other {
                                HStack(spacing: 4) {
                                    GSRadio(title: "", selected: model.settings.palette == .other) {
                                        model.settings.palette = .other
                                        model.normalise()
                                    }
                                    Button("Get other...") { model.overlay = .getOther }
                                        .buttonStyle(GSButtonStyle())
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
                    GSGroup(title: "Rendering algorithm") {
                        ForEach(RenderAlgorithm.allCases, id: \.rawValue) { algorithm in
                            GSRadio(title: algorithm.title, selected: model.settings.algorithm == algorithm,
                                    enabled: algorithm != .errorDiffusion || model.errorDiffusionAllowed) {
                                model.settings.algorithm = algorithm
                            }
                        }
                    }
                }
                .frame(width: 190)

                VStack(alignment: .leading, spacing: 6) {
                    Button("Info on these options") {
                        model.overlay = .info("Remap options", """
                            Graphic mode picks the IIgs screen mode of the result.
                            Palette to use picks its colors; Calculated finds the best ones for this picture.
                            Pattern dither mixes palette colors in small patterns; Error diffusion is \
                            offered for grayscale and black & white palettes.
                            Quick remap ignores every option and gives a one-screen preview.
                            """)
                    }
                    .buttonStyle(GSButtonStyle())

                    Group {
                        Text("Vertical scaling: from \(natural.1) to \(sizes.wanted.1) (\(ratio(model.settings.vStep)))")
                        scaleSlider($model.settings.vStep)
                        Text("Horizontal: from \(natural.0) to \(sizes.wanted.0) (\(ratio(model.settings.hStep)))")
                        scaleSlider($model.settings.hStep)
                        if sizes.clipped != sizes.wanted {
                            Text("Clipped to \(sizes.clipped.0) x \(sizes.clipped.1)")
                        }
                        if let s = model.statistics {
                            Text("Distinct colors used: \(s.distinct)")
                            Text("Distribution: \(model.distribution(s))")
                        } else {
                            Text("Counting colors...")
                        }
                    }
                    .font(GS.font)
                    .foregroundColor(.black)

                    GSGroup(title: "Other options") {
                        GSCheckbox(title: "Integral scaling only", isOn: $model.settings.integral)
                        GSCheckbox(title: "Clip Horiz. before Vert.", isOn: $model.settings.clipHorizFirst)
                        GSCheckbox(title: "Clip to one screen", isOn: $model.settings.clipOneScreen)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                        Button("Quick remap") { model.runRemap(quick: true) }.buttonStyle(GSButtonStyle())
                        Button("Normal remap") { model.runRemap(quick: false) }
                            .buttonStyle(GSButtonStyle(isDefault: true))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
        }
        .fixedSize()
    }

    /// Stand-in for the original's scroll bars: arrows step through the scale ratios.
    private func scaleSlider(_ step: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            Button("<") { step.wrappedValue = max(0, step.wrappedValue - 1) }.buttonStyle(.plain).frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(white: 0.75))
                    Rectangle().fill(Color.white).border(Color.black, width: 1).frame(width: 16)
                        .offset(x: (geo.size.width - 16) * CGFloat(step.wrappedValue) / CGFloat(scaleSteps.count - 1))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let f = min(1, max(0, value.location.x / geo.size.width))
                    step.wrappedValue = Int((f * CGFloat(scaleSteps.count - 1)).rounded())
                })
            }
            Button(">") { step.wrappedValue = min(scaleSteps.count - 1, step.wrappedValue + 1) }
                .buttonStyle(.plain).frame(width: 18)
        }
        .font(GS.font)
        .frame(height: 14)
        .border(Color.black, width: 1)
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
