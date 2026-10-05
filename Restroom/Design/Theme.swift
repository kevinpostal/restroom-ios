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

    static func font(_ style: Style) -> Font {
        switch style {
        case .display: return .system(size: 34, weight: .bold)
        case .title: return .system(size: 20, weight: .semibold)
        case .body: return .system(size: 17, weight: .regular)
        case .mono: return .system(size: 15, design: .monospaced)
        case .label: return .system(size: 12, weight: .semibold)
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

enum Amenity: CaseIterable, Equatable {
    case accessible, unisex, changingTable

    var title: String {
        switch self {
        case .accessible: return "Accessible"
        case .unisex: return "Unisex"
        case .changingTable: return "Changing table"
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
