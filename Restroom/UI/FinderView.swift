import CoreLocation
import MapKit
import SwiftUI

struct FinderView: View {
    @EnvironmentObject private var model: FinderModel
    @EnvironmentObject private var location: LocationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var usedFirstFix = false
    /// Last camera region reported by the map; zoom buttons scale it. nil until the map has laid out.
    @State private var region: MKCoordinateRegion?
    /// Centre last searched because the user panned there; `recenter()` must not snap the camera back to it.
    @State private var explored: CLLocationCoordinate2D?
    @State private var detent: SheetDetent = .medium

    /// Zoom limits as latitude span (degrees): ~110 m to ~170 km.
    private static let minSpan = 0.001, maxSpan = 1.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                map
                    // Camera framing + Apple attribution stay in the band above the sheet
                    // (WWDC23 "Meet MapKit for SwiftUI": safeAreaInset keeps map content clear of your UI).
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: min(detent, .medium).height(in: geo.size.height) + geo.safeAreaInsets.bottom)
                    }
                    .ignoresSafeArea()
                zoomControls.fixedSize().padding(Theme.unit)
                searchingTile
                    .padding(Theme.unit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .animation(.linear(duration: 0.2), value: model.busy)
                BottomSheet(detent: $detent) { sheetHeader } content: { sheetBody }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .task {
            if UITestMode.isActive {
                if !UITestMode.flag("-uitest-denied") { model.useCurrentLocation(UITestMode.start) }
            } else {
                location.request()
            }
        }
        .onReceive(location.$location.compactMap { $0 }) { loc in
            guard !usedFirstFix else { return }
            usedFirstFix = true
            model.useCurrentLocation(loc)
        }
        .onChange(of: model.center?.latitude) { _, _ in recenter() }
        .onChange(of: model.center?.longitude) { _, _ in recenter() }
        .onChange(of: model.selected?.id) { _, _ in
            detent = .medium
            if let r = model.selected { move(to: r.coordinate, span: 600) } else { recenter() }
        }
    }

    /// After a search the map moves; bring the sheet back to half so the new area is visible.
    private func recenter() {
        guard let c = model.center else { return }
        if let e = explored, meters(e, c) < 1 { return }
        detent = .medium
        move(to: c, span: 1500)
    }

    /// A user pan past an eighth of the visible span (never under 200 m) searches the new area, closing any
    /// open place card. Programmatic moves land on `model.center` or the selected pin, so they never pass
    /// the threshold: the pin's own 600 m framing is well under 200 m of drift.
    private func exploreIfPanned(_ r: MKCoordinateRegion) {
        let anchor = model.selected?.coordinate ?? model.center
        guard let anchor else { return }
        guard meters(anchor, r.center) > max(200, r.span.latitudeDelta * 111_000 / 8) else { return }
        explored = r.center
        model.explore(r.center)
        model.selected = nil
    }

    private func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func move(to c: CLLocationCoordinate2D, span: CLLocationDistance) {
        set(MKCoordinateRegion(center: c, latitudinalMeters: span, longitudinalMeters: span))
    }

    private func zoom(by factor: Double) {
        guard var r = region else { return }
        let f = min(max(factor, Self.minSpan / r.span.latitudeDelta), Self.maxSpan / r.span.latitudeDelta)
        guard f != 1 else { return }
        r.span.latitudeDelta *= f
        r.span.longitudeDelta *= f
        set(r)
    }

    private func set(_ region: MKCoordinateRegion) {
        if reduceMotion {
            camera = .region(region)
        } else {
            withAnimation { camera = .region(region) }
        }
    }

    /// Spoken/testable width of the visible map, e.g. "0.9 mi".
    private var spanText: String {
        guard let r = region else { return "" }
        let meters = r.span.latitudeDelta * 111_000
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road)) + " across"
    }

    /// Sheet drag area: place-card header when a pin is selected, otherwise search → title row (Apple Maps order).
    @ViewBuilder private var sheetHeader: some View {
        if let r = model.selected {
            DetailHeader(restroom: r, close: { model.selected = nil })
        } else {
            SearchField(onFocus: { detent = .large })
                .padding(.horizontal, 2 * Theme.unit)
            HStack(alignment: .center) {
                Text(model.centerLabel).themed(.title).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("header.title")
                Spacer()
                refreshButton
                locateButton
            }
            .padding(.horizontal, 2 * Theme.unit).padding(.vertical, Theme.unit)
        }
    }

    @ViewBuilder private var sheetBody: some View {
        if let r = model.selected {
            DetailView(restroom: r)
                .id(r.id) // fresh ScrollView offset when switching pins
        } else {
            Hairline()
            ResultList()
        }
    }

    private var locateButton: some View {
        Button {
            usedFirstFix = false
            if UITestMode.isActive {
                if !UITestMode.flag("-uitest-denied") { model.useCurrentLocation(UITestMode.start) }
            } else {
                location.request()
                if let loc = location.location { model.useCurrentLocation(loc) }
            }
        } label: {
            Circle().fill(Theme.red).frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use my location")
        .accessibilityHint("Searches near your current location")
        .accessibilityIdentifier("map.locate")
    }

    /// Hairline ring: a full circle at rest, a turning three-quarter arc while a fetch is in flight.
    private var refreshButton: some View {
        Button { model.refresh() } label: {
            LoadingRing(busy: model.busy)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
        .accessibilityValue(model.busy ? "Loading" : "")
        .accessibilityHint("Searches this area again")
        .accessibilityIdentifier("header.refresh")
    }

    /// Map is always visible (convention); the no-centre message lives in the sheet's ResultList.
    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(model.restrooms) { r in
                Annotation(r.name, coordinate: r.coordinate, anchor: .center) {
                    Button { model.selected = r } label: {
                        Pin(selected: model.selected?.id == r.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(r.name.isEmpty ? "Restroom" : r.name)
                    .accessibilityHint("Shows details")
                    .accessibilityAddTraits(model.selected?.id == r.id ? .isSelected : [])
                    .accessibilityIdentifier("pin.\(r.id)")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .overlay {   // paper wash while a fetch is in flight: the pins underneath are the old area
            Theme.paper.opacity(model.busy ? 0.35 : 0)
                .allowsHitTesting(false)
                .animation(.linear(duration: 0.2), value: model.busy)
        }
        .onMapCameraChange(frequency: .continuous) { region = $0.region }
        .onMapCameraChange(frequency: .onEnd) { exploreIfPanned($0.region) }
        .accessibilityLabel("Map of nearby restrooms")
        .accessibilityValue(spanText)
        .accessibilityIdentifier("map")
    }

    /// Two stacked paper tiles, hairline ink border, + / − glyphs. Each at least 44 pt.
    private var zoomControls: some View {
        VStack(spacing: 0) {
            zoomButton("+", label: "Zoom in", id: "map.zoomIn") { zoom(by: 0.5) }
            Rectangle().fill(Theme.ink).frame(height: 1)
            zoomButton("−", label: "Zoom out", id: "map.zoomOut") { zoom(by: 2) }
        }
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// Paper tile at the map's top-left while a fetch is in flight: small turning ring + "Searching…".
    /// The map itself gets a light paper wash so the stale pins read as provisional.
    @ViewBuilder private var searchingTile: some View {
        if model.busy {
            HStack(spacing: Theme.unit) {
                LoadingRing(busy: true).scaleEffect(0.5).frame(width: 16, height: 16)
                Text("Searching…").themed(.mono)
            }
            .padding(.horizontal, 1.5 * Theme.unit)
            .frame(minHeight: 44)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Searching this area")
            .accessibilityIdentifier("map.loading")
        }
    }

    private func zoomButton(_ glyph: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(Theme.font(.title))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Map marker: paper tile, hairline ink border, restroom pictogram (head + body). Selected = red tile.
/// Visual tile is 26/32 pt; the hit target is padded to 44 pt.
private struct Pin: View {
    let selected: Bool

    var body: some View {
        let side: CGFloat = selected ? 32 : 26
        let fg = selected ? Theme.paper : Theme.ink
        ZStack {
            Rectangle().fill(selected ? Theme.red : Theme.paper)
            Rectangle().strokeBorder(selected ? Theme.red : Theme.ink, lineWidth: 1.5)
            VStack(spacing: side * 0.06) {
                Circle().fill(fg).frame(width: side * 0.22, height: side * 0.22)
                Rectangle().fill(fg).frame(width: side * 0.3, height: side * 0.34)
            }
        }
        .frame(width: side, height: side)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct SearchField: View {
    @EnvironmentObject private var model: FinderModel
    let onFocus: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Theme.unit) {
            HStack {
                TextField("Search a place", text: $model.query)
                    .themed(.body)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { Task { await model.search(model.query) } }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Search a place")
                    .accessibilityIdentifier("search.field")
                if !model.query.isEmpty {
                    Button("×") { model.query = "" }
                        .themed(.title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Clear search")
                        .accessibilityIdentifier("search.clear")
                }
            }
            Hairline()
        }
        .onChange(of: focused) { _, new in if new { onFocus() } }
    }
}

private struct ResultList: View {
    @EnvironmentObject private var model: FinderModel
    @EnvironmentObject private var location: LocationService

    var body: some View {
        List {
            switch model.state {
            case .loading:
                note("Loading…").accessibilityLabel("Loading restrooms")
            case .empty:
                note("No restrooms within range.")
            case .failed(let msg):
                VStack(alignment: .leading, spacing: Theme.unit) {
                    Text(msg).themed(.body).accessibilityIdentifier("state.message")
                    action("Retry", id: "state.retry") { model.reload() }
                }
                .listRowBackground(Theme.paper)
                .listRowSeparatorTint(Theme.line)
            case .idle:
                if location.authorization == .denied || location.authorization == .restricted {
                    VStack(alignment: .leading, spacing: Theme.unit) {
                        Text("Location is off. Search a place above or enable it in Settings.").themed(.body)
                            .accessibilityIdentifier("state.message")
                        action("Open Settings", id: "state.settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    .listRowBackground(Theme.paper)
                    .listRowSeparatorTint(Theme.line)
                } else {
                    note("Finding you…")
                }
            case .loaded:
                ForEach(model.restrooms) { r in
                    Button { model.selected = r } label: { RestroomRow(restroom: r) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("row.\(r.id)")
                        .listRowBackground(Theme.paper)
                        .listRowSeparatorTint(Theme.line)
                        .listRowInsets(EdgeInsets(top: 2 * Theme.unit, leading: 2 * Theme.unit, bottom: 2 * Theme.unit, trailing: 2 * Theme.unit))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .accessibilityIdentifier("list")
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Theme.font(.mono)).foregroundStyle(Theme.graphite)
            .accessibilityIdentifier("state.note")
            .listRowBackground(Theme.paper)
            .listRowSeparatorTint(Theme.line)
    }

    private func action(_ title: String, id: String, _ perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .font(Theme.font(.title)).foregroundStyle(Theme.red)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier(id)
    }
}

private struct RestroomRow: View {
    let restroom: Restroom
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    private var name: String { restroom.name.isEmpty ? "Restroom" : restroom.name }

    private var voiceOverLabel: String {
        let amenities = restroom.kind == .restroom
            ? (restroom.amenities.isEmpty ? "no amenity details" : restroom.amenities.map(\.title).joined(separator: ", "))
            : "\(restroom.kind.tag ?? ""), usually has restrooms"
        return [name, restroom.addressLine, restroom.access?.spoken ?? "", restroom.distanceSpoken ?? "", amenities]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    text
                    distance
                }
            } else {
                HStack(alignment: .top, spacing: 2 * Theme.unit) {
                    text
                    Spacer(minLength: Theme.unit)
                    distance
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows details and directions")
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).themed(.title)
            if !restroom.addressLine.isEmpty {
                Text(restroom.addressLine).font(Theme.font(.body)).foregroundStyle(Theme.graphite)
            }
            if let tag = restroom.kind.tag {
                Text(tag).themed(.label)
            }
            if let a = restroom.access {
                Text(a.title).themed(.mono)
            }
            if !restroom.amenities.isEmpty {
                if withoutColor {
                    Text(restroom.amenities.map(\.title).joined(separator: " · ")).themed(.label).padding(.top, 4)
                } else {
                    HStack(spacing: Theme.unit) {
                        ForEach(restroom.amenities, id: \.self) { Badge(kind: $0, size: 12) }
                    }
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private var distance: some View {
        if let d = restroom.distanceText {
            Text(d).themed(.mono)
        }
    }
}
