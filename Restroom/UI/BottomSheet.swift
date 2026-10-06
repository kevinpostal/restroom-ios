import SwiftUI

/// Resting heights of the bottom panel.
enum SheetDetent: CaseIterable, Comparable {
    case collapsed, medium, large

    /// Grabber strip + one 44 pt row.
    static let collapsedHeight: CGFloat = 112

    /// Panel height for an available (safe-area) height.
    func height(in available: CGFloat) -> CGFloat {
        switch self {
        case .collapsed: Self.collapsedHeight
        case .medium: (available / 2).rounded()
        case .large: available
        }
    }

    var spoken: String {
        switch self {
        case .collapsed: "Collapsed"
        case .medium: "Half height"
        case .large: "Expanded"
        }
    }
}

/// Edge-to-edge paper panel pinned to the bottom with three detents, in the Rams/Bauhaus language
/// (square corners, hairline top edge, ink grabber). The system sheet on iOS 26 floats inset with
/// rounded corners and scales its content at partial detents, which also breaks the text-clipping audit.
/// Dragging the grabber or `header` moves the panel; `content` (a List/ScrollView) scrolls on its own.
struct BottomSheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.height
            let rest = detent.height(in: available)
            let height = min(max(rest - dragOffset, SheetDetent.collapsed.height(in: available)), available)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    grabber
                    header()
                }
                .gesture(drag(available: available))
                content()
            }
            // Content is laid out for at least the medium height so a collapsed panel clips it rather than squeezing it.
            .frame(height: max(height, SheetDetent.medium.height(in: available)), alignment: .top)
            .frame(width: geo.size.width, height: height, alignment: .top)
            .clipped()
            .background(Theme.paper)
            .overlay(alignment: .top) { Hairline() }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: detent)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sheet")
        }
    }

    private var grabber: some View {
        Rectangle().fill(Theme.ink).frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("Panel")
            .accessibilityValue(detent.spoken)
            .accessibilityHint("Swipe up or down to resize")
            .accessibilityAdjustableAction { direction in
                let all = SheetDetent.allCases
                guard let i = all.firstIndex(of: detent) else { return }
                switch direction {
                case .increment: if i + 1 < all.count { detent = all[i + 1] }
                case .decrement: if i > 0 { detent = all[i - 1] }
                @unknown default: break
                }
            }
            .accessibilityIdentifier("sheet.grabber")
    }

    private func drag(available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                let target = detent.height(in: available) - value.predictedEndTranslation.height
                let nearest = SheetDetent.allCases.min { abs($0.height(in: available) - target) < abs($1.height(in: available) - target) } ?? .medium
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                    detent = nearest
                    dragOffset = 0
                }
            }
    }
}
