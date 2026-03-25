import SwiftUI

// ── Navigation principale : 3 onglets ──
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Accueil",    systemImage: "house.fill")
                }

            HistoryView()
                .tabItem {
                    Label("Historique", systemImage: "clock.fill")
                }

            StatsView()
                .tabItem {
                    Label("Stats",      systemImage: "chart.bar.fill")
                }
        }
        .accentColor(.orange)
        .preferredColorScheme(.dark)
    }
}
