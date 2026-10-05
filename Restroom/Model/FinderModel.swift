import CoreLocation
import Foundation
import MapKit

enum LoadState: Equatable {
    case idle, loading, loaded, empty
    case failed(String)
}

@MainActor
final class FinderModel: ObservableObject {
    @Published var restrooms: [Restroom] = []
    @Published var center: CLLocationCoordinate2D?
    @Published var centerLabel: String = "Near you"
    @Published var state: LoadState = .idle
    @Published var selected: Restroom?
    @Published var query: String = ""

    private let api: RestroomProvider
    private var inflight: Task<Void, Never>?

    init(api: RestroomProvider = RefugeAPI.shared) {
        self.api = api
    }

    func useCurrentLocation(_ loc: CLLocation) {
        center = loc.coordinate
        centerLabel = "Near you"
        reload()
    }

    func search(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        state = .loading
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        let item: MKMapItem?
        do { item = try await MKLocalSearch(request: request).start().mapItems.first }
        catch { item = nil }
        guard let item else {
            state = .failed("No place named “\(q)”")
            return
        }
        center = item.placemark.coordinate
        centerLabel = item.name ?? q
        reload()
    }

    func reload() {
        guard let center else { return }
        inflight?.cancel()
        state = .loading
        inflight = Task { [api] in
            do {
                let result = try await api.nearby(center, perPage: 50)
                guard !Task.isCancelled else { return }
                restrooms = result
                state = result.isEmpty ? .empty : .loaded
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Awaitable form for tests.
    func reloadAndWait() async {
        reload()
        await inflight?.value
    }
}
