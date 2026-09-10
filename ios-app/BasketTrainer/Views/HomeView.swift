import SwiftUI

// ─────────────────────────────────────────────────
// ACCUEIL — Dashboard + accès rapide
// ─────────────────────────────────────────────────
private enum HomeSheet: Identifiable {
    case manual
    case routine
    case slotsConfig
    case profile
    case watchSetup

    var id: String {
        switch self {
        case .manual:          return "manual"
        case .routine:         return "routine"
        case .slotsConfig:     return "slotsConfig"
        case .profile:         return "profile"
        case .watchSetup:      return "watchSetup"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store:        SessionStore
    @EnvironmentObject var garmin:       GarminManager
    @EnvironmentObject var profileStore: ProfileStore
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
                                Text("Mes entraînements")
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

                        newWorkoutButton
                            .padding(.horizontal, 20)

                        routineButton
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .profile
                    } label: {
                        if let data = profileStore.profile?.photoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .manual:
                    LiveWorkoutView()
                case .routine:
                    LiveRoutineView()
                case .slotsConfig:
                    SlotsView()
                        .environmentObject(store)
                        .environmentObject(garmin)
                case .profile:
                    if profileStore.profile != nil {
                        ProfileView()
                            .environmentObject(profileStore)
                    } else {
                        EditProfileView(isOnboarding: true)
                            .environmentObject(profileStore)
                    }
                case .watchSetup:
                    WatchSetupView()
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
                    activeSheet = .watchSetup
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
                    Text("Suivi tir par tir, sans la montre")
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

    private var routineButton: some View {
        Button {
            activeSheet = .routine
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entraînement complet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Plusieurs séries, comme sur la montre")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
