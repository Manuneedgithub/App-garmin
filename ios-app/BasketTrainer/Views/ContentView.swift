import SwiftUI

// ── Navigation principale : 4 onglets ──
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

            CourtView()
                .tabItem {
                    Label("Terrain",    systemImage: "sportscourt")
                }
        }
        .accentColor(.orange)
    }
}
