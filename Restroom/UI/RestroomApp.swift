import SwiftUI

@main
struct RestroomApp: App {
    @StateObject private var model = FinderModel()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            FinderView()
                .environmentObject(model)
                .environmentObject(location)
        }
    }
}
