import SwiftUI

// ─────────────────────────────────────────────────
// DÉTAIL D'UNE SÉANCE — Tir par tir + résumé
// ─────────────────────────────────────────────────
struct SessionDetailView: View {
    let session: WorkoutSession
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteAlert = false
    @State private var showEdit = false

    // Toujours lire depuis le store pour refléter les modifications
    private var current: WorkoutSession {
        store.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    scoreHeader

                    statsGrid

                    // Séries (séances complexes)
                    if let series = current.series, series.count > 1 {
                        seriesList(series)
                    } else if !current.results.isEmpty {
                        shotsGrid(current.results)
                    }

                    metaInfo

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.orange)
                    }
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
        }
        .alert("Supprimer cette séance ?", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                store.deleteSession(session)
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) {
            EditSessionView(session: current)
        }
    }

    // ── Composants ──

    private var scoreHeader: some View {
        VStack(spacing: 0) {
            // Identité exercice
            HStack(spacing: 12) {
                Text(current.displayEmoji)
                    .font(.title)
                    .frame(width: 48, height: 48)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(current.date.formatted(.dateTime.day().month().hour().minute()))
                        if let dur = current.duration, dur > 0 {
                            Text("·")
                            Text("\(Int(dur / 60)) min")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()

            // Score
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(current.madeShots)/\(current.totalShots)")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 40)

                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", current.percentage))
                        .font(.title.bold())
                        .foregroundStyle(percentageColor(current.percentage))
                        .monospacedDigit()
                    Text(current.performanceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)

            Divider()

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 5)
                    Rectangle()
                        .fill(percentageColor(current.percentage))
                        .frame(width: geo.size.width * CGFloat(current.percentage / 100), height: 5)
                }
            }
            .frame(height: 5)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(current.madeShots)",  label: "Réussis",  color: .green)
            StatTile(value: "\(current.missedShots)", label: "Ratés",   color: .red)
            StatTile(value: "\(current.totalShots)",  label: "Total",   color: .orange)
        }
    }

    @ViewBuilder
    private func targetBadge(_ target: Int) -> some View {
        Text("🎯 \(target)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.8))
            .clipShape(Capsule())
    }

    private func seriesList(_ series: [ShotSeries]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détail par série")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(Array(series.enumerated()), id: \.offset) { idx, ser in
                VStack(spacing: 8) {
                    HStack {
                        Text("\(ser.exerciseType.emoji) Série \(idx + 1) — \(ser.exerciseType.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let target = ser.targetMade { targetBadge(target) }
                        Spacer()
                        Text("\(ser.madeShots)/\(ser.totalShots)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(String(format: "%.0f%%", ser.percentage))
                            .font(.caption.bold())
                            .foregroundStyle(percentageColor(ser.percentage))
                    }

                    if !ser.results.isEmpty {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(Array(ser.results.enumerated()), id: \.offset) { i, made in
                                ShotDot(index: i + 1, made: made)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func shotsGrid(_ results: [Bool]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détail des tirs")
                .font(.headline)
                .foregroundStyle(.primary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, made in
                    ShotDot(index: index + 1, made: made)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var metaInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(icon: "calendar",
                    label: "Date",
                    value: current.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
            Divider()
            InfoRow(icon: "applewatch",
                    label: "Source",
                    value: current.sentFromWatch ? "Garmin FR255" : "iPhone")
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}

// ─────────────────────────────────────────────────
// Sous-composants
// ─────────────────────────────────────────────────

struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ShotDot: View {
    let index: Int
    let made:  Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(made ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
            Text("\(index)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }
}

struct InfoRow: View {
    let icon:  String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.orange)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
