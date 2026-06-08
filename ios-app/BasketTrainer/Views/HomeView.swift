import SwiftUI

// ─────────────────────────────────────────────────
// ACCUEIL — Dashboard + accès rapide
// ─────────────────────────────────────────────────
private enum HomeSheet: Identifiable {
    case manual
    case slotsConfig

    var id: String {
        switch self {
        case .manual:          return "manual"
        case .slotsConfig:     return "slotsConfig"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    @State private var activeSheet: HomeSheet? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        watchConnectionRow
                            .padding(.horizontal, 20)

                        Button {
                            activeSheet = .slotsConfig
                        } label: {
                            HStack {
                                Image(systemName: "dumbbell.fill")
                                    .foregroundStyle(.orange)
                                Text("Configurer les entraînements montre")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        quickStats
                            .padding(.horizontal, 20)

                        newWorkoutButton
                            .padding(.horizontal, 20)

                        if !store.recentSessions.isEmpty {
                            recentSessionsList
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Basket Trainer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .manual:
                    ManualSessionView()
                case .slotsConfig:
                    SlotsView()
                        .environmentObject(store)
                        .environmentObject(garmin)
                }
            }
        }
    }

    private var watchConnectionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: garmin.connectedDevice != nil ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .foregroundStyle(garmin.connectedDevice != nil ? .green : .secondary)
            Text(garmin.connectedDevice != nil ? "Montre connectée" : "Montre non connectée")
                .font(.subheadline)
                .foregroundStyle(garmin.connectedDevice != nil ? .primary : .secondary)
            Spacer()
            if garmin.connectedDevice == nil {
                Button("Connecter") {
                    garmin.connectWatch()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            MiniStatCard(value: "\(store.totalSessions)", label: "Séances",  icon: "figure.basketball")
            MiniStatCard(value: "\(store.totalShots)",   label: "Tirs",      icon: "basketball")
            MiniStatCard(value: String(format: "%.0f%%", store.overallPct),  label: "Réussite", icon: "percent")
        }
    }

    private var newWorkoutButton: some View {
        Button {
            activeSheet = .manual
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouvel entraînement")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Saisie manuelle ou depuis la montre")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Récentes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            ForEach(store.recentSessions.prefix(5)) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ─────────────────────────────────────────────────
// Petite carte stat (pour l'accueil)
// ─────────────────────────────────────────────────
struct MiniStatCard: View {
    let value: String
    let label: String
    let icon:  String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ─────────────────────────────────────────────────
// Ligne d'une séance dans la liste
// ─────────────────────────────────────────────────
struct SessionRowView: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 14) {
            Text(session.displayEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if session.isComplex {
                        Text("\(session.series?.count ?? 0) séries")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    if session.sentFromWatch {
                        Text("⌚")
                            .font(.caption2)
                    }
                }
                HStack(spacing: 4) {
                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                    if let dur = session.duration, dur > 0 {
                        Text("·")
                        Text("\(Int(dur / 60)) min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.madeShots)/\(session.totalShots)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", session.percentage))
                    .font(.caption.bold())
                    .foregroundStyle(percentageColor(session.percentage))
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
