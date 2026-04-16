import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let url = launchOptions?[.url] as? URL {
            print("[AppDelegate] launch url: \(url)")
            GarminManager.shared.handleIncomingURL(url)
        }
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("[AppDelegate] open url: \(url)")
        GarminManager.shared.handleIncomingURL(url)
        return true
    }
}

@main
struct BasketTrainerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store  = SessionStore.shared
    @StateObject private var garmin = GarminManager.shared

    init() {
        GarminManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(garmin)
                .onOpenURL { url in
                    print("[App] onOpenURL: \(url)")
                    garmin.handleIncomingURL(url)
                }
        }
    }
}
