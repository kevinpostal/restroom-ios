import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus
    @Published var location: CLLocation?

    private let manager = CLLocationManager()
    /// When set (UI tests), the system manager is never asked for anything.
    private let simulated: CLAuthorizationStatus?

    init(simulatedAuthorization: CLAuthorizationStatus? = nil) {
        simulated = simulatedAuthorization
        authorization = simulatedAuthorization ?? manager.authorizationStatus
        super.init()
        guard simulatedAuthorization == nil else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        guard simulated == nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // Head start: the system's last fix (often seconds old from another app) beats waiting 1–3 s for ours.
            if location == nil, let last = manager.location, -last.timestamp.timeIntervalSinceNow < 120 { location = last }
            manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
