import SwiftUI

// ── Navigation principale : 5 onglets ──
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

            TrophiesView()
                .tabItem {
                    Label("Trophées",   systemImage: "trophy.fill")
                }

            CourtView()
                .tabItem {
                    Label("Terrain",    systemImage: "sportscourt")
                }
        }
        .accentColor(.orange)
        .overlay(CelebrationOverlayView())
    }
}
