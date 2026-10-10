import CoreText
import SwiftUI

enum AppFont: String, CaseIterable {
    case shaston640, shaston320, system

    var title: String {
        switch self {
        case .shaston640: return "Shaston 640"
        case .shaston320: return "Shaston 320"
        case .system: return "Geneva (Mac system font)"
        }
    }
}

/// Apple IIgs desktop look: 640-mode colours, hairline black borders, inverse selection.
enum GS {
    static let desktop = Color(red: 0.60, green: 0.60, blue: 1.0)
    /// Shaston is the IIgs system font (Kreative Software's recreation, bundled with the app).
    private static let registered: Bool = {
        for name in ["Shaston640", "Shaston320"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }()
    /// The typeface picked in Preferences.
    static var appearance = AppFont.shaston640
    static var font: Font {
        _ = registered
        switch appearance {
        case .shaston640: return Font.custom("Shaston640", size: 16)
        case .shaston320: return Font.custom("Shaston320", size: 8)
        case .system: return Font.custom("Geneva", size: 12)
        }
    }
    static let rowHeight: CGFloat = 16
}

/// A IIgs document window: black title bar when active, hairline frame.
struct GSWindow<Content: View>: View {
    let title: String
    var active = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(GS.font)
                .lineLimit(1)
                .foregroundColor(active ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(active ? Color.black : Color.white)
            Rectangle().fill(Color.black).frame(height: 1)
            content
        }
        .background(Color.white)
        .border(Color.black, width: 1)
    }
}

/// Rounded-rectangle push button; the default button gets the heavy outline.
struct GSButtonStyle: ButtonStyle {
    var isDefault = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GS.font)
            .foregroundColor(configuration.isPressed ? .white : (enabled ? .black : .gray))
            .padding(.horizontal, 12)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 10).fill(configuration.isPressed ? Color.black : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(enabled ? Color.black : Color.gray,
                                                               lineWidth: isDefault ? 3 : 1))
    }
}

struct GSRadio: View {
    let title: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(enabled ? Color.black : Color.gray, lineWidth: 1).frame(width: 11, height: 11)
                    if selected { Circle().fill(Color.black).frame(width: 5, height: 5) }
                }
                Text(title).font(GS.font).foregroundColor(enabled ? .black : .gray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GSCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                ZStack {
                    Rectangle().stroke(Color.black, lineWidth: 1).frame(width: 11, height: 11)
                    if isOn {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 11, y: 11))
                            p.move(to: CGPoint(x: 11, y: 0)); p.addLine(to: CGPoint(x: 0, y: 11))
                        }
                        .stroke(Color.black, lineWidth: 1)
                        .frame(width: 11, height: 11)
                    }
                }
                Text(title).font(GS.font).foregroundColor(.black)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A list with inverse-video selection and a IIgs scroll bar.
struct GSList: View {
    let items: [String]
    @Binding var selection: Int
    let rows: Int
    var onDoubleClick: (() -> Void)?
    @State private var top = 0

    private var maxTop: Int { max(0, items.count - rows) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    let index = top + row
                    let text = index < items.count ? items[index] : ""
                    let chosen = index == selection && index < items.count
                    Text(text)
                        .font(GS.font)
                        .lineLimit(1)
                        .foregroundColor(chosen ? .white : .black)
                        .padding(.leading, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: GS.rowHeight)
                        .background(chosen ? Color.black : Color.white)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if index < items.count {
                                selection = index
                                onDoubleClick?()
                            }
                        }
                        .onTapGesture { if index < items.count { selection = index } }
                }
            }
            Rectangle().fill(Color.black).frame(width: 1)
            scrollBar
        }
        .frame(height: CGFloat(rows) * GS.rowHeight)
        .onChange(of: items.count) { _ in top = 0 }
    }

    private var scrollBar: some View {
        VStack(spacing: 0) {
            arrow(up: true) { top = max(0, top - 1) }
            Rectangle().fill(Color.black).frame(height: 1)
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Rectangle().fill(maxTop > 0 ? Color(white: 0.75) : Color.white)
                    if maxTop > 0 {
                        let thumb = max(12, geo.size.height * CGFloat(rows) / CGFloat(items.count))
                        Rectangle()
                            .fill(Color.white)
                            .border(Color.black, width: 1)
                            .frame(height: thumb)
                            .offset(y: (geo.size.height - thumb) * CGFloat(top) / CGFloat(maxTop))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let half = geo.size.height / 2
                    top = location.y < half ? max(0, top - rows) : min(maxTop, top + rows)
                }
            }
            Rectangle().fill(Color.black).frame(height: 1)
            arrow(up: false) { top = min(maxTop, top + 1) }
        }
        .frame(width: 18)
    }

    private func arrow(up: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Path { p in
                p.move(to: CGPoint(x: 9, y: up ? 3 : 12))
                p.addLine(to: CGPoint(x: 3, y: up ? 9 : 6))
                p.addLine(to: CGPoint(x: 6, y: up ? 9 : 6))
                p.addLine(to: CGPoint(x: 6, y: up ? 12 : 3))
                p.addLine(to: CGPoint(x: 12, y: up ? 12 : 3))
                p.addLine(to: CGPoint(x: 12, y: up ? 9 : 6))
                p.addLine(to: CGPoint(x: 15, y: up ? 9 : 6))
                p.closeSubpath()
            }
            .stroke(Color.black, lineWidth: 1)
            .frame(width: 18, height: 15)
            .background(Color.white)
        }
        .buttonStyle(.plain)
    }
}

/// A modal dialog box with the IIgs double frame.
struct GSDialog<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(Color.white)
            .border(Color.black, width: 3)
            .padding(3)
            .background(Color.white)
            .border(Color.black, width: 1)
    }
}

/// A labelled group box as used in the Remap dialog.
struct GSGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(GS.font).foregroundColor(.black).underline()
            content
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .border(Color.black, width: 1)
    }
}

/// A one-line edit field with the IIgs hairline frame.
struct GSField: View {
    let label: String
    @Binding var text: String
    var width: CGFloat = 150

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(GS.font).foregroundColor(.black)
            Spacer(minLength: 0)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(GS.font)
                .foregroundColor(.black)
                .padding(.horizontal, 3)
                .frame(width: width, height: 18)
                .background(Color.white)
                .border(Color.black, width: 1)
        }
    }
}
