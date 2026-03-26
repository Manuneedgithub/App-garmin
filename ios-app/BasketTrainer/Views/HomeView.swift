import SwiftUI

// ─────────────────────────────────────────────────
// ACCUEIL — Dashboard + accès rapide
// ─────────────────────────────────────────────────
struct HomeView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    @State private var showManualEntry  = false
    @State private var prefillTemplate: ComplexTemplate? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Mode guidé (prioritaire si actif) ──
                        if garmin.guidedTemplate != nil {
                            GuidedSessionBanner()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        header
                        quickStats
                        newWorkoutButton

                        // ── Templates complexes ──
                        if !store.templates.isEmpty {
                            TemplatesView { template in
                                prefillTemplate = template
                                showManualEntry = true
                            }
                        }

                        // ── Séances récentes ──
                        if !store.recentSessions.isEmpty {
                            recentSessionsList
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.3), value: garmin.guidedTemplate != nil)
                }
            }
            .navigationTitle("Basket Trainer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    connectionBadge
                }
            }
            .sheet(isPresented: $showManualEntry, onDismiss: { prefillTemplate = nil }) {
                ManualSessionView(prefillTemplate: prefillTemplate)
            }
        }
    }

    // ── Composants ──

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bonjour 👋")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Prêt à s'entraîner ?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
        }
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            MiniStatCard(value: "\(store.totalSessions)", label: "Séances",   icon: "figure.basketball")
            MiniStatCard(value: "\(store.totalShots)",   label: "Tirs",       icon: "basketball")
            MiniStatCard(value: String(format: "%.0f%%", store.overallPct),
                                                          label: "Réussite",   icon: "percent")
        }
    }

    private var newWorkoutButton: some View {
        Button {
            prefillTemplate = nil
            showManualEntry = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Nouvel entraînement")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.5))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Récentes")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(store.recentSessions.prefix(5)) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectionBadge: some View {
        Button {
            garmin.showDeviceSelection()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(garmin.lastSyncDate != nil ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                if let last = garmin.lastSyncDate {
                    Text("Synchro \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connecter montre")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.07))
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
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.isComplex {
                        Text("Complexe")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.madeShots)/\(session.totalShots)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(String(format: "%.0f%%", session.percentage))
                    .font(.caption)
                    .foregroundStyle(percentageColor(session.percentage))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
