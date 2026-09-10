import SwiftUI

// ─────────────────────────────────────────────────
// PROFIL — identité + stats globales + zones de tir
// ─────────────────────────────────────────────────
struct ProfileView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @State private var showEdit = false

    private var profile: UserProfile { profileStore.profile ?? UserProfile(username: "", statsSummary: .empty) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        identityHeader
                        statsGrid
                        zoneBreakdown
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { showEdit = true }
                        .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditProfileView(isOnboarding: false)
            }
        }
    }

    // ── Identité ──

    private var identityHeader: some View {
        VStack(spacing: 12) {
            if let data = profile.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.orange.opacity(0.6))
            }

            Text(profile.username)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                if let age = profile.age {
                    infoPill("\(age) ans")
                }
                if let sex = profile.sex {
                    infoPill(sex.label)
                }
                if let position = profile.position {
                    infoPill(position.label)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }

    // ── Stats globales ──

    private var statsGrid: some View {
        let s = profile.statsSummary
        return VStack(alignment: .leading, spacing: 12) {
            Text("Statistiques globales")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                StatTile(value: "\(s.totalSessions)", label: "Séances", color: .orange)
                StatTile(value: "\(s.totalShots)",    label: "Tirs",     color: .blue)
            }
            HStack(spacing: 12) {
                StatTile(value: String(format: "%.0f%%", s.overallFGPercentage), label: "FG%", color: percentageColor(s.overallFGPercentage))
                StatTile(value: "\(s.longestStreak) j", label: "Meilleure série", color: .red)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // ── Zones de tir ──

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zones de tir")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(profile.statsSummary.zonePerformance) { zone in
                VStack(spacing: 6) {
                    HStack {
                        Text(zone.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(zone.shots == 0 ? "—" : String(format: "%.0f%%", zone.percentage))
                            .font(.subheadline.bold())
                            .foregroundStyle(zone.shots == 0 ? .secondary : percentageColor(zone.percentage))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(percentageColor(zone.percentage))
                                .frame(width: geo.size.width * CGFloat(zone.percentage / 100), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
