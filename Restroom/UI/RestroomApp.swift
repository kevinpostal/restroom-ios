import SwiftUI

@main
struct RestroomApp: App {
    @StateObject private var model = FinderModel(
        api: UITestMode.isActive ? FixtureProvider() : RefugeAPI.shared,
        places: UITestMode.isActive ? FixtureResolver() : LocalSearchResolver()
    )
    @StateObject private var location = LocationService(
        simulatedAuthorization: UITestMode.isActive ? (UITestMode.flag("-uitest-denied") ? .denied : .authorizedWhenInUse) : nil
    )

    var body: some Scene {
        WindowGroup {
            FinderView()
                .environmentObject(model)
                .environmentObject(location)
        }
    }
}
