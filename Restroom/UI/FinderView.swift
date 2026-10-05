import CoreLocation
import MapKit
import SwiftUI

struct FinderView: View {
    @EnvironmentObject private var model: FinderModel
    @EnvironmentObject private var location: LocationService
    @State private var camera: MapCameraPosition = .automatic
    @State private var usedFirstFix = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                Hairline()
                mapPane.frame(height: geo.size.height * 0.44)
                Hairline()
                ResultList()
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $model.selected) { r in
            DetailView(restroom: r)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.paper)
        }
        .task { location.request() }
        .onReceive(location.$location.compactMap { $0 }) { loc in
            guard !usedFirstFix else { return }
            usedFirstFix = true
            model.useCurrentLocation(loc)
        }
        .onChange(of: model.center?.latitude) { _, _ in recenter() }
        .onChange(of: model.center?.longitude) { _, _ in recenter() }
        .onChange(of: model.selected?.id) { _, _ in
            guard let r = model.selected else { return }
            move(to: r.coordinate, span: 600)
        }
    }

    private func recenter() {
        guard let c = model.center else { return }
        move(to: c, span: 1500)
    }

    private func move(to c: CLLocationCoordinate2D, span: CLLocationDistance) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restroom").themed(.label)
                    Text(model.centerLabel).themed(.display).lineLimit(1)
                }
                Spacer()
                Button {
                    usedFirstFix = false
                    location.request()
                    if let loc = location.location { model.useCurrentLocation(loc) }
                } label: {
                    Circle().fill(Theme.red).frame(width: 32, height: 32)
                }
                .accessibilityLabel("Use my location")
            }
            SearchField()
        }
        .padding(2 * Theme.unit)
    }

    private var mapPane: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(model.restrooms) { r in
                Annotation(r.name, coordinate: r.coordinate, anchor: .center) {
                    Pin(selected: model.selected?.id == r.id)
                        .onTapGesture { model.selected = r }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
    }
}

/// Map marker: paper tile, hairline ink border, restroom pictogram (head + body). Selected = red tile.
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
    }
}

private struct SearchField: View {
    @EnvironmentObject private var model: FinderModel

    var body: some View {
        VStack(spacing: Theme.unit) {
            HStack {
                TextField("Search a place", text: $model.query)
                    .themed(.body)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await model.search(model.query) } }
                if !model.query.isEmpty {
                    Button("×") { model.query = "" }
                        .themed(.title)
                        .accessibilityLabel("Clear search")
                }
            }
            Hairline()
        }
    }
}

private struct ResultList: View {
    @EnvironmentObject private var model: FinderModel
    @EnvironmentObject private var location: LocationService

    var body: some View {
        List {
            switch model.state {
            case .loading:
                note("Loading…")
            case .empty:
                note("No restrooms within range.")
            case .failed(let msg):
                VStack(alignment: .leading, spacing: Theme.unit) {
                    Text(msg).themed(.body)
                    Button("Retry") { model.reload() }.font(Theme.font(.title)).foregroundStyle(Theme.red)
                }
                .listRowBackground(Theme.paper)
                .listRowSeparatorTint(Theme.line)
            case .idle:
                if location.authorization == .denied || location.authorization == .restricted {
                    VStack(alignment: .leading, spacing: Theme.unit) {
                        Text("Location is off. Search a place above or enable it in Settings.").themed(.body)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(Theme.font(.title)).foregroundStyle(Theme.red)
                    }
                    .listRowBackground(Theme.paper)
                    .listRowSeparatorTint(Theme.line)
                } else {
                    note("Finding you…")
                }
            case .loaded:
                ForEach(model.restrooms) { r in
                    RestroomRow(restroom: r)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selected = r }
                        .listRowBackground(Theme.paper)
                        .listRowSeparatorTint(Theme.line)
                        .listRowInsets(EdgeInsets(top: 2 * Theme.unit, leading: 2 * Theme.unit, bottom: 2 * Theme.unit, trailing: 2 * Theme.unit))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Theme.font(.mono)).foregroundStyle(Theme.graphite)
            .listRowBackground(Theme.paper)
            .listRowSeparatorTint(Theme.line)
    }
}

private struct RestroomRow: View {
    let restroom: Restroom

    var body: some View {
        HStack(alignment: .top, spacing: 2 * Theme.unit) {
            VStack(alignment: .leading, spacing: 4) {
                Text(restroom.name.isEmpty ? "Restroom" : restroom.name).themed(.title).lineLimit(1)
                if !restroom.addressLine.isEmpty {
                    Text(restroom.addressLine).font(Theme.font(.body)).foregroundStyle(Theme.graphite).lineLimit(1)
                }
                if !restroom.amenities.isEmpty {
                    HStack(spacing: Theme.unit) {
                        ForEach(restroom.amenities, id: \.self) { Badge(kind: $0, size: 12) }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: Theme.unit)
            if let d = restroom.distanceText {
                Text(d).themed(.mono)
            }
        }
    }
}
