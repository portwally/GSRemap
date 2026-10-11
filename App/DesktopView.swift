import SCCore
import SwiftUI

struct MenuEntry {
    let title: String
    /// One or two sentences shown by Help and by Menu item help.
    let help: String
    var enabled: Bool
    var action: (() -> Void)?

    init(_ title: String, _ help: String = "", enabled: Bool = true, action: (() -> Void)? = nil) {
        self.title = title
        self.help = help
        self.enabled = enabled
        self.action = action
    }

    static let divider = MenuEntry("-", enabled: false)
}

struct DesktopView: View {
    @ObservedObject var model: AppModel
    static let size = CGSize(width: 640, height: 400)

    var body: some View {
        ZStack(alignment: .topLeading) {
            GS.desktop
            if let picture = model.desktopImage {
                // Larger pictures lose their bottom; smaller ones sit in the middle.
                Image(decorative: picture, scale: 1)
                    .interpolation(.none)
                    .frame(width: DesktopView.size.width, height: DesktopView.size.height,
                           alignment: picture.height > Int(DesktopView.size.height) ? .top : .center)
                    .clipped()
            }
            windows.padding(.top, 20)
            if model.openMenu != nil {
                Color.clear.contentShape(Rectangle()).onTapGesture { model.openMenu = nil }
            }
            menuBar
            overlay
        }
        .frame(width: DesktopView.size.width, height: DesktopView.size.height)
        .clipped()
        .id(model.appFont)
    }

    // MARK: Windows

    private var windows: some View {
        HStack(alignment: .top, spacing: 8) {
            GSWindow(title: "Load formats", active: model.activeWindow == 0) {
                VStack(spacing: 0) {
                    GSList(items: model.categories.map(\.name), selection: Binding(
                        get: { model.categoryIndex },
                        set: { model.categoryIndex = $0; model.formatIndex = 0 }), rows: 7)
                    Rectangle().fill(Color.black).frame(height: 1)
                    VStack(spacing: 2) {
                        HStack {
                            Text("\u{25B2} Computer type").font(GS.font).foregroundColor(.black)
                            Spacer()
                            if !model.queue.isEmpty {
                                Button("Load next") { model.loadNext() }.buttonStyle(GSButtonStyle())
                            }
                            Button("Load") { model.load() }.buttonStyle(GSButtonStyle(isDefault: true))
                        }
                        HStack {
                            Button("Info on format") {
                                let f = model.formats[min(model.formatIndex, model.formats.count - 1)]
                                model.overlay = .info(f.name, f.trueColor
                                    ? "Loads as a true color image; the Remap dialog then turns it into a screen image."
                                    : "Loads directly as a screen image.")
                            }
                            .buttonStyle(GSButtonStyle())
                            Spacer()
                            Text("Specific type \u{25BC}").font(GS.font).foregroundColor(.black)
                        }
                    }
                    .padding(4)
                    Rectangle().fill(Color.black).frame(height: 1)
                    GSList(items: model.formats.map(\.listName), selection: $model.formatIndex, rows: 7) {
                        model.load()
                    }
                }
            }
            .frame(width: 290)

            VStack(spacing: 8) {
                GSWindow(title: "Save formats", active: model.activeWindow == 1) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button("Save") { model.save() }.buttonStyle(GSButtonStyle())
                                .disabled(model.screen == nil)
                            Spacer()
                        }
                        .padding(4)
                        Rectangle().fill(Color.black).frame(height: 1)
                        GSList(items: FormatRegistry.saveFormats.map(\.name), selection: $model.saveIndex, rows: 5) {
                            model.save()
                        }
                    }
                }
                GSWindow(title: model.imageTitle, active: model.activeWindow == 2) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            GSRadio(title: "Screen", selected: !model.showTrueColor && !model.showMono,
                                    enabled: model.screen != nil) {
                                model.showTrueColor = false
                                model.showMono = false
                            }
                            GSRadio(title: "True color", selected: model.showTrueColor && !model.showMono,
                                    enabled: model.trueColor != nil) {
                                model.showTrueColor = true
                                model.showMono = false
                            }
                            GSRadio(title: "Mono", selected: model.showMono, enabled: model.mono != nil) {
                                model.showMono = true
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 18)
                        Rectangle().fill(Color.black).frame(height: 1)
                        ZStack {
                            Color.white
                            if let image = model.currentCGImage() {
                                Image(decorative: image, scale: 1)
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: 322)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: DesktopView.size.height - 20, alignment: .top)
    }

    // MARK: Menu bar

    var menuBar: some View {
        let menus = self.menus
        return HStack(spacing: 0) {
            ForEach(menus.indices, id: \.self) { i in
                let open = model.openMenu == i
                Text(menus[i].0)
                    .font(GS.font)
                    .foregroundColor(open ? .white : .black)
                    .padding(.horizontal, 9)
                    .frame(height: 19)
                    .background(open ? Color.black : Color.white)
                    .contentShape(Rectangle())
                    .onTapGesture { model.openMenu = open ? nil : i }
                    // The last menus open leftward so they stay on the desktop.
                    .overlay(alignment: i >= menus.count - 2 ? .topTrailing : .topLeading) {
                        if open { dropDown(menus[i].1).offset(y: 19) }
                    }
                    .zIndex(open ? 2 : 1)
            }
            Spacer(minLength: 0)
        }
        .frame(width: DesktopView.size.width, height: 19, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 1).offset(y: 1) }
    }

    private func dropDown(_ entries: [MenuEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries.indices, id: \.self) { i in
                let entry = entries[i]
                if entry.title == "-" {
                    Rectangle().fill(Color.gray).frame(height: 1).padding(.vertical, 3)
                } else {
                    MenuRow(entry: entry, picking: model.pickingHelp) {
                        model.openMenu = nil
                        if model.pickingHelp {
                            model.pickingHelp = false
                            model.overlay = .info(entry.title, entry.help.isEmpty ? "No help for this item." : entry.help)
                            return false
                        }
                        return true
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .fixedSize()
        .background(Color.white)
        .border(Color.black, width: 1)
        .background(Color.black.offset(x: 2, y: 2))
    }

    // MARK: Dialogs

    @ViewBuilder private var overlay: some View {
        if let overlay = model.overlay {
            ZStack {
                if overlay == .fullScreen {
                    Color.black
                    if let screen = model.screen, let image = ModernImage.cgImage(screen) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else if case .viewer(let kind) = overlay {
                    ViewerOverlay(model: model, kind: kind)
                } else {
                    Color.black.opacity(0.001)
                    switch overlay {
                    case .remap: RemapDialog(model: model)
                    case .getOther: GetOtherDialog(model: model)
                    case .working(let text):
                        GSDialog { Text(text).font(GS.font).foregroundColor(.black).frame(width: 200) }.fixedSize()
                    case .about:
                        message("GS Remap", """
                            Based on SuperConvert 4.0 for the Apple IIgs.
                            Original program by Jason Harper, updates by Ian Brumby.
                            Copyright 1992-1997 Seven Hills Software Corporation.
                            Shaston and Print Char 21 fonts by Kreative Software.
                            """)
                    case .preferences: preferences
                    case .choose: chooser
                    case .saveOptions: saveOptions
                    case .factor(let kind): factorDialog(kind)
                    case .toMono(let fromScreen): toMonoDialog(fromScreen)
                    case .fromMono(let toScreen): fromMonoDialog(toScreen)
                    case .info(let title, let text): message(title, text)
                    case .help: HelpDialog(model: model, menus: menus)
                    case .examine: ExamineDialog(model: model)
                    case .printOptions: PrintOptionsDialog(model: model)
                    case .fullScreen, .viewer: EmptyView()
                    }
                }
            }
            .frame(width: DesktopView.size.width, height: DesktopView.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if overlay == .fullScreen { model.overlay = nil }
                if case .viewer = overlay { model.overlay = nil }
            }
        }
    }

    private func factorDialog(_ kind: Int) -> some View {
        GSDialog {
            VStack(alignment: .leading, spacing: 8) {
                Text(["Blur image", "Sharpen image", "Find edges"][kind]).font(GS.font).bold().foregroundColor(.black)
                GSField(label: "Factor (0-99):", text: $model.factorText, width: 60)
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button("OK") { model.runFactorFilter(kind) }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 240, alignment: .leading)
        }
        .fixedSize()
    }

    private func choices<T: Equatable>(_ title: String, _ items: [(String, T)], _ value: Binding<T>) -> some View {
        GSGroup(title: title) {
            ForEach(items.indices, id: \.self) { i in
                GSRadio(title: items[i].0, selected: value.wrappedValue == items[i].1) { value.wrappedValue = items[i].1 }
            }
        }
    }

    private func toMonoDialog(_ fromScreen: Bool) -> some View {
        let w = (fromScreen ? model.screen?.width : model.trueColor?.width) ?? 0
        let h = (fromScreen ? model.screen?.height : model.trueColor?.height) ?? 0
        let sizes = [("1X", 1), ("2X", 2), ("4X", 4)]
        return GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text(fromScreen ? "Screen to monochrome" : "True color to monochrome")
                    .font(GS.font).bold().foregroundColor(.black)
                HStack(alignment: .top, spacing: 8) {
                    choices("Horizontal size", sizes, $model.monoXScale)
                    choices("Vertical size", sizes, $model.monoYScale)
                    choices("Rendering method", MonoRendering.allCases.map { ($0.title, $0) }, $model.monoMethod)
                        .frame(width: 170)
                }
                Text("Resulting image: \(w * model.monoXScale) x \(h * model.monoYScale) monochrome pixels")
                    .font(GS.font).foregroundColor(.black)
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button("Convert") { model.convertToMono(fromScreen: fromScreen) }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 440, alignment: .leading)
        }
        .fixedSize()
    }

    private func fromMonoDialog(_ toScreen: Bool) -> some View {
        let size = model.mono.map { model.fromMono.resultSize(of: $0) } ?? (0, 0)
        return GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text(toScreen ? "Monochrome to screen" : "Monochrome to true color")
                    .font(GS.font).bold().foregroundColor(.black)
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 6) {
                        choices("Resulting image", toScreen ? [("320 mode", false), ("640 mode", true)]
                                : [("320-sized pixels", false), ("640-sized pixels", true)], $model.fromMono.mode640)
                        choices("Aspect ratio", MonoAspect.allCases.map { ($0.title, $0) }, $model.fromMono.aspect)
                    }
                    .frame(width: 150)
                    VStack(spacing: 6) {
                        choices("Scaling", [("1:1", 1), ("1:2", 2), ("1:4", 4)], $model.fromMono.scaling)
                        choices("Shrink as", MonoShrink.allCases.map { ($0.title, $0) }, $model.fromMono.shrink)
                            .opacity(model.fromMono.scaling == 1 ? 0.35 : 1)
                            .allowsHitTesting(model.fromMono.scaling != 1)
                    }
                }
                Text("Monochrome pixels: \(model.mono?.width ?? 0) x \(model.mono?.height ?? 0)")
                    .font(GS.font).foregroundColor(.black)
                Text("Resulting pixels: \(size.0) x \(size.1)").font(GS.font).foregroundColor(.black)
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button("Convert") { model.convertFromMono(toScreen: toScreen) }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 450, alignment: .leading)
        }
        .fixedSize()
    }

    private var saveOptions: some View {
        let format = FormatRegistry.saveFormats[model.saveIndex]
        return GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text(format.name).font(GS.font).bold().foregroundColor(.black)
                switch format.options {
                case .icon:
                    GSField(label: "Used for files named:", text: $model.saveOptions.iconName)
                    GSField(label: "File type $ (00 = any):", text: $model.iconFileTypeText, width: 60)
                    GSField(label: "Aux type $ (0000 = any):", text: $model.iconAuxTypeText, width: 60)
                    GSField(label: "Opens with program:", text: $model.saveOptions.iconApplication)
                    GSCheckbox(title: "Color icon (Finder may not recolor it)", isOn: $model.saveOptions.iconColor)
                    GSCheckbox(title: "White is transparent", isOn: $model.saveOptions.whiteIsTransparent)
                    Text("The small icon is a reduced copy of the picture.").font(GS.font).foregroundColor(.black)
                case .iconResource:
                    GSCheckbox(title: "Color icon", isOn: $model.saveOptions.iconColor)
                    GSCheckbox(title: "White is transparent", isOn: $model.saveOptions.whiteIsTransparent)
                case .hex:
                    GSField(label: "Before each line:", text: $model.saveOptions.hexBefore)
                    GSField(label: "Between bytes:", text: $model.saveOptions.hexBetween)
                    GSField(label: "After each line:", text: $model.saveOptions.hexAfter)
                    Text("Sample line of generated output:").font(GS.font).foregroundColor(.black)
                    Text(model.saveOptions.hexBefore + ["01", "23", "45", "67"].joined(separator: model.saveOptions.hexBetween)
                         + model.saveOptions.hexAfter)
                        .font(GS.font).foregroundColor(.black).lineLimit(1)
                case .none:
                    EmptyView()
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button(format.addsToExistingFile ? "Choose file..." : "Save...") { model.finishSave() }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .frame(width: 360, alignment: .leading)
        }
        .fixedSize()
    }

    private var chooser: some View {
        GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text("This file holds \(model.choices.count) pictures. Load which one?")
                    .font(GS.font).foregroundColor(.black)
                GSList(items: model.choices, selection: $model.choiceIndex, rows: 9) { model.confirmChoice() }
                    .border(Color.black, width: 1)
                HStack {
                    Spacer()
                    Button("Cancel") { model.overlay = nil }.buttonStyle(GSButtonStyle())
                    Button("Load") { model.confirmChoice() }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 320, alignment: .leading)
        }
        .fixedSize()
    }

    private var preferences: some View {
        GSDialog {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferences").font(GS.font).bold().foregroundColor(.black)
                GSGroup(title: "Appearance: font") {
                    ForEach(AppFont.allCases, id: \.rawValue) { choice in
                        GSRadio(title: choice.title, selected: model.appFont == choice) { model.appFont = choice }
                    }
                }
                HStack {
                    Spacer()
                    Button("OK") { model.overlay = nil }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 300, alignment: .leading)
        }
        .fixedSize()
    }

    private func message(_ title: String, _ text: String) -> some View {
        GSDialog {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(GS.font).bold().foregroundColor(.black)
                Text(text).font(GS.font).foregroundColor(.black).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Continue") { model.overlay = nil }
                        .buttonStyle(GSButtonStyle(isDefault: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 340, alignment: .leading)
        }
        .fixedSize()
    }
}

private struct MenuRow: View {
    let entry: MenuEntry
    /// Menu item help is on: dimmed items can be picked too.
    let picking: Bool
    /// Closes the menu; returns false when the click was used up by Menu item help.
    let close: () -> Bool
    @State private var hovering = false

    var body: some View {
        let lit = hovering && (entry.enabled || picking)
        Text(entry.title)
            .font(GS.font)
            .foregroundColor(lit ? .white : (entry.enabled ? .black : .gray))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 17)
            .background(lit ? Color.black : Color.white)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                guard entry.enabled || picking else { return }
                if close() { entry.action?() }
            }
    }
}
