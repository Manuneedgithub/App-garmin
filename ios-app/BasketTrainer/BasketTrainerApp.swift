import SwiftUI

@main
struct BasketTrainerApp: App {
    @StateObject private var store   = SessionStore.shared
    @StateObject private var garmin  = GarminManager.shared

    init() {
        GarminManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(garmin)
                .onOpenURL { url in
                    garmin.handleIncomingURL(url)
                }
        }
    }
}
