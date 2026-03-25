import SwiftUI
import Charts

// ─────────────────────────────────────────────────
// STATS — Vue globale par exercice
// ─────────────────────────────────────────────────
struct StatsView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedExercise: ExerciseType? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // ── Résumé global ──
                        globalSummary

                        // ── Graphique progression globale ──
                        if store.sessions.count >= 2 {
                            progressChart
                        }

                        // ── Stats par exercice ──
                        exerciseStatsList

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Statistiques")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // ── Composants ──

    private var globalSummary: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                GlobalStatCard(value: "\(store.totalSessions)",
                               label: "Séances",
                               icon: "figure.basketball",
                               color: .orange)
                GlobalStatCard(value: "\(store.totalShots)",
                               label: "Tirs totaux",
                               icon: "basketball",
                               color: .blue)
            }
            HStack(spacing: 12) {
                let overall = store.overallPct
                GlobalStatCard(value: String(format: "%.1f%%", overall),
                               label: "Réussite globale",
                               icon: "percent",
                               color: colorForPct(overall))
                GlobalStatCard(value: "\(store.allStats().count)",
                               label: "Exercices pratiqués",
                               icon: "list.bullet",
                               color: .purple)
            }
        }
    }

    // Graphique des 15 dernières séances (taux de réussite)
    private var progressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progression (15 dernières séances)")
                .font(.headline)
                .foregroundStyle(.white)

            let data = store.sessions
                .sorted { $0.date < $1.date }
                .suffix(15)
                .enumerated()
                .map { (index: $0.offset + 1, pct: $0.element.percentage) }

            Chart {
                ForEach(data, id: \.index) { point in
                    LineMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(30)
                }

                // Ligne de référence 70%
                RuleMark(y: .value("Objectif", 70))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("70%").font(.caption2).foregroundStyle(.green.opacity(0.7))
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 160)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Liste des stats par exercice
    private var exerciseStatsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Par exercice")
                .font(.headline)
                .foregroundStyle(.white)

            if store.allStats().isEmpty {
                Text("Lance des séances pour voir tes stats ici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(store.allStats(), id: \.exerciseType) { stats in
                    ExerciseStatRow(stats: stats)
                }
            }
        }
    }

    private func colorForPct(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}

// ─────────────────────────────────────────────────
// Carte stat globale
// ─────────────────────────────────────────────────
struct GlobalStatCard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ─────────────────────────────────────────────────
// Ligne de stat d'un exercice avec barre de progression
// ─────────────────────────────────────────────────
struct ExerciseStatRow: View {
    let stats: ExerciseStats

    private var pctColor: Color {
        if stats.avgPercentage >= 70 { return .green }
        if stats.avgPercentage >= 50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(stats.exerciseType.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.exerciseType.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(stats.totalSessions) séance\(stats.totalSessions > 1 ? "s" : "") · \(stats.totalShots) tirs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", stats.avgPercentage))
                    .font(.title3.bold())
                    .foregroundStyle(pctColor)
            }

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(pctColor)
                        .frame(width: geo.size.width * (stats.avgPercentage / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
