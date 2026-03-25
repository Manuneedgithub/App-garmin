import SwiftUI

@main
struct BasketTrainerApp: App {
    @StateObject private var store   = SessionStore.shared
    @StateObject private var garmin  = GarminManager.shared

    init() {
        GarminManager.shared.setup()
        customizeAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(garmin)
        }
    }

    private func customizeAppearance() {
        // Barre de navigation semi-transparente
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes    = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
