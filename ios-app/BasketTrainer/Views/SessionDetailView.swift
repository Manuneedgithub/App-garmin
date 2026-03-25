import SwiftUI

// ─────────────────────────────────────────────────
// DÉTAIL D'UNE SÉANCE — Tir par tir + résumé
// ─────────────────────────────────────────────────
struct SessionDetailView: View {
    let session: WorkoutSession
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // ── Header score ──
                    scoreHeader

                    // ── Stats résumé ──
                    statsGrid

                    // ── Tirs un par un ──
                    if !session.results.isEmpty {
                        shotsGrid
                    }

                    // ── Métadonnées ──
                    metaInfo

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle(session.exerciseType.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
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
    }

    // ── Composants ──

    private var scoreHeader: some View {
        VStack(spacing: 8) {
            Text(session.exerciseType.emoji)
                .font(.system(size: 52))

            Text("\(session.madeShots) / \(session.totalShots)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(String(format: "%.0f%%", session.percentage))
                .font(.title2.bold())
                .foregroundStyle(percentageColor(session.percentage))

            Text(session.performanceLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(percentageColor(session.percentage).opacity(0.15))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(session.madeShots)",  label: "Réussis",  color: .green)
            StatTile(value: "\(session.missedShots)", label: "Ratés",   color: .red)
            StatTile(value: "\(session.totalShots)",  label: "Total",   color: .orange)
        }
    }

    private var shotsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détail des tirs")
                .font(.headline)
                .foregroundStyle(.white)

            // Grille de points colorés (10 par ligne)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 10)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(session.results.enumerated()), id: \.offset) { index, made in
                    ShotDot(index: index + 1, made: made)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var metaInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(icon: "calendar",       label: "Date",
                    value: session.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
            InfoRow(icon: "applewatch",     label: "Source",
                    value: session.sentFromWatch ? "Garmin FR255" : "iPhone")
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
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
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
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
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}
