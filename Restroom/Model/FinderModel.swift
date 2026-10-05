import CoreLocation
import Foundation

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
    private let places: PlaceResolver
    private var inflight: Task<Void, Never>?

    init(api: RestroomProvider = RefugeAPI.shared, places: PlaceResolver = LocalSearchResolver()) {
        self.api = api
        self.places = places
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
        guard let place = await places.resolve(q) else {
            state = .failed("No place named “\(q)”")
            return
        }
        center = place.coordinate
        centerLabel = place.name
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
