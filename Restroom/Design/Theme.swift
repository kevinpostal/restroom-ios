import SwiftUI

/// Rams × Bauhaus: one accent, paper/ink, 8pt grid, hairlines, no radii, no shadows.
enum Theme {
    static let unit: CGFloat = 8

    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let graphite = Color("Graphite")
    static let line = Color("Line")
    static let red = Color("Red")
    static let blue = Color("Blue")
    static let yellow = Color("Yellow")

    enum Style { case display, title, body, mono, label }

    /// Text-style based so every size scales with Dynamic Type (defaults: 34/20/17/15/12 pt).
    static func font(_ style: Style) -> Font {
        switch style {
        case .display: return .largeTitle.weight(.bold)
        case .title: return .title3.weight(.semibold)
        case .body: return .body
        case .mono: return .system(.subheadline, design: .monospaced)
        case .label: return .caption.weight(.semibold)
        }
    }
}

extension View {
    func themed(_ style: Theme.Style) -> some View {
        modifier(ThemedText(style: style))
    }
}

private struct ThemedText: ViewModifier {
    let style: Theme.Style
    func body(content: Content) -> some View {
        switch style {
        case .display: content.font(Theme.font(.display)).tracking(-0.5).foregroundStyle(Theme.ink)
        case .title: content.font(Theme.font(.title)).foregroundStyle(Theme.ink)
        case .body: content.font(Theme.font(.body)).foregroundStyle(Theme.ink)
        case .mono: content.font(Theme.font(.mono)).foregroundStyle(Theme.ink)
        case .label: content.font(Theme.font(.label)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.graphite)
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

/// Ink ring, 32 pt: closed at rest; while `busy` it opens to a three-quarter arc and turns once a second
/// (holds still under Reduce Motion). Doubles as the refresh glyph and the loading indicator.
struct LoadingRing: View {
    let busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: busy ? 0.75 : 1)
            .stroke(Theme.ink, lineWidth: 1.5)
            .frame(width: 32, height: 32)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(busy && !reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : .linear(duration: 0.2), value: turning)
            .animation(.linear(duration: 0.2), value: busy)
            .onChange(of: busy, initial: true) { _, b in turning = b && !reduceMotion }
    }
}

enum Amenity: CaseIterable, Equatable {
    case accessible, unisex, changingTable

    /// Full name: detail card and VoiceOver. "Accessible" on Refuge means ADA/wheelchair accessible.
    var title: String {
        switch self {
        case .accessible: return "ADA accessible"
        case .unisex: return "Unisex"
        case .changingTable: return "Changing table"
        }
    }

    /// One word for the row, next to the badge, so the colour never carries meaning alone.
    var short: String {
        switch self {
        case .accessible: return "ADA"
        case .unisex: return "Unisex"
        case .changingTable: return "Changing"
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Badge: View {
    let kind: Amenity
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .accessible: Circle().fill(Theme.red)
            case .unisex: Rectangle().fill(Theme.blue)
            case .changingTable: Triangle().fill(Theme.yellow)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind.title)
    }
}
