import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The island follows Coucou (MIT, © 2026 Louis Raillé; see THIRD_PARTY_NOTICES.md): its sizes
// (the notch, the notch with two 80-point ears, a 640-point card), a spring with a little overshoot
// when it grows and a quick ease when it shrinks, concave "ears" that let the folded island flow
// into the top edge of the screen, tabs and icons in the strip beside the notch, dark rounded
// plain cards, capsule pills that brighten under the pointer, a mascot that springs
// between its places, and a thin bar that counts down before the island folds by itself.
// The mascot, the colours, the words and the sounds are StudyNotch's own.

// MARK: - Shape and layout helpers

/// Square at the top, rounded at the bottom. With `ear` above zero the top corners flare out
/// into small concave fillets, the way the hardware notch meets the screen edge.
struct IslandShape: Shape {
    var cornerRadius: CGFloat
    var ear: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, ear) }
        set {
            cornerRadius = newValue.first
            ear = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let e = max(0, min(ear, w / 4, h))
        let r = max(0, min(cornerRadius, (w - 2 * e) / 2, h / 2))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))
        if e > 0 {
            path.addArc(center: CGPoint(x: w, y: e), radius: e,
                        startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        }
        path.addLine(to: CGPoint(x: w - e, y: h - r))
        path.addArc(center: CGPoint(x: w - e - r, y: h - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: e + r, y: h))
        path.addArc(center: CGPoint(x: e + r, y: h - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: e, y: e))
        if e > 0 {
            path.addArc(center: CGPoint(x: 0, y: e), radius: e,
                        startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
        }
        path.closeSubpath()
        return path
    }
}

/// Lays chips out left to right and wraps to the next line when they run out of room.
struct Flow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Colour tokens. They mirror DESIGN.md; add a colour there before adding one here.
/// The app's interface is white and grey on black, nothing else. The one spoonful of colour is the
/// mascot's eyes (MascotLook.Hue), and it is never used for anything in the interface.
enum Ink {
    /// White: the one primary action on a card, the text the user picked, progress.
    static let primary = Color.white
    /// The one spoonful of colour: a faint light rising behind a card and behind the mascot, in the
    /// state's colour (focus and done green #7CE38B, drift amber #FFB25E, writing violet #C9A6FF).
    /// It is only ever a soft gradient, never a fill, a dot, a border or text.
    enum Glow {
        static let green = Color(red: 0.486, green: 0.89, blue: 0.545)
        static let amber = Color(red: 1.0, green: 0.698, blue: 0.369)
        static let violet = Color(red: 0.788, green: 0.651, blue: 1.0)
        static let focus = green.opacity(0.32)
        static let drift = amber.opacity(0.4)
        static let done = green.opacity(0.4)
        static let writing = violet.opacity(0.22)
        static let rest = Color.white.opacity(0.1)
    }
    static let muted = Color.white.opacity(0.62)
    static let line = Color.white.opacity(0.16)
    static let fill = Color.white.opacity(0.12)
    static let fillHover = Color.white.opacity(0.2)
    /// Paper #FFFFFF and pen ink #14233B, from the website palette: only the mascot's speech bubble uses them.
    static let paper = Color.white
    static let pen = Color(red: 0.078, green: 0.137, blue: 0.231)
    /// Card #141518 on the island's black, with an edge of white 3.5%.
    static let card = Color(red: 0.078, green: 0.082, blue: 0.094)
    static let cardEdge = Color.white.opacity(0.035)
    /// Pill #0E0F11, the selected tab #1D1F23.
    static let pill = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let tabOn = Color(red: 0.114, green: 0.122, blue: 0.137)
    /// Icons and pill labels at rest #8E939C and #6B7079; island text #F5F6F8.
    static let icon = Color(red: 0.557, green: 0.576, blue: 0.612)
    static let faint = Color(red: 0.42, green: 0.439, blue: 0.475)
    static let text = Color(red: 0.961, green: 0.965, blue: 0.973)
}

/// Shared motion values.
enum Motion {
    static let open = Animation.spring(response: 0.5, dampingFraction: 0.72)
    static let close = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    static let contentIn = Animation.spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
    static let contentOut = Animation.easeIn(duration: 0.16)
    static let hover = Animation.spring(response: 0.2, dampingFraction: 0.7)
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.6)
}

/// Outgoing content fades, shrinks a touch and blurs; incoming content does the reverse.
private struct ContentFade: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .blur(radius: shown ? 0 : 8)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(Motion.contentIn),
            removal: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(Motion.contentOut)
        )
    }
}

/// Every control answers the pointer: it brightens and swells on hover and gives on press.
struct Springy: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SpringyBody(configuration: configuration)
    }

    private struct SpringyBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .brightness(hovered ? 0.08 : 0)
                .scaleEffect(configuration.isPressed ? 0.94 : (hovered ? 1.04 : 1))
                .animation(configuration.isPressed ? Motion.press : Motion.hover, value: configuration.isPressed)
                .animation(Motion.hover, value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

/// Every action is one of these: at least 28 points tall, so it is easy to hit with the pointer.
struct Chip: View {
    let title: String
    var primary = false
    var selected = false
    var icon: String?
    let action: () -> Void

    init(_ title: String, primary: Bool = false, selected: Bool = false, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.primary = primary
        self.selected = selected
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title)
                    .font(.system(size: 12.5, weight: primary || selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .foregroundColor(primary ? .black : .white)
            .background(Capsule().fill(primary ? Ink.primary : (selected ? Ink.tabOn : Ink.fill)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected && !primary ? 0.22 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(Springy())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Ink.muted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Ink.fill))
                .contentShape(Circle())
        }
        .buttonStyle(Springy())
        .accessibilityLabel("Close")
    }
}

/// The state is never told by colour alone: each one has its own shape.
struct GlyphView: View {
    let glyph: Glyph
    @State private var pulse = false

    var body: some View {
        Group {
            switch glyph {
            case .none:
                Circle().fill(Color.white.opacity(0.35)).frame(width: 7, height: 7)
            case .focus:
                Circle().fill(Ink.text).frame(width: 8, height: 8)
            case .drift:
                Circle().stroke(Ink.text, lineWidth: 2).frame(width: 8, height: 8)
            case .thinking:
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Ink.text).frame(width: 4, height: 4)
                    }
                }
                .opacity(pulse ? 0.35 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                }
            case .rest:
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.white).frame(width: 3, height: 9)
                    RoundedRectangle(cornerRadius: 1).fill(Color.white).frame(width: 3, height: 9)
                }
            }
        }
        .frame(width: 18, height: 12)
    }
}

struct QuoteView: View {
    let quote: String?
    let imagePath: String?

    var body: some View {
        if let imagePath, let image = NSImage(contentsOfFile: imagePath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 110, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let quote, !quote.isEmpty {
            // The picked sentence looks highlighted, the way it does on the page.
            Text(quote.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 12.5))
                .foregroundColor(Ink.text)
                .lineLimit(3)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct QuestionField: View {
    @Binding var text: String
    let placeholder: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused(focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(focused.wrappedValue ? Color.white.opacity(0.38) : Ink.line, lineWidth: 1))
            .animation(Motion.hover, value: focused.wrappedValue)
    }
}

