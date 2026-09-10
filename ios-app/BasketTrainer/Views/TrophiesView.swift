import SwiftUI

struct TrophiesView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        let progress = TrophyEngine.evaluate(sessions: store.sessions)
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(TrophyCategory.allCases) { category in
                            TrophyCategoryCard(
                                category: category,
                                currentValue: progress.currentValues[category] ?? 0,
                                unlockedTrophies: store.unlockedTrophies
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Trophées")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// ─────────────────────────────────────────────────
// Carte d'une piste de trophées : icône + valeur actuelle,
// 8 pastilles de palier, barre de progression vers le prochain.
//
// NOTE: unlock status/dates always come from `unlockedTrophies`
// (SessionStore's persisted record), never from a fresh
// TrophyEngine.evaluate() re-run — a live re-run could show fewer
// unlocks than history once earned (e.g. after deleting a session),
// which would violate the "never revoke" rule. Only the *current
// value* / progress-bar math uses the live recompute.
// ─────────────────────────────────────────────────
struct TrophyCategoryCard: View {
    let category: TrophyCategory
    let currentValue: Int
    let unlockedTrophies: [String: Date]
    @State private var selectedTier: Int? = nil

    private func isUnlocked(_ tier: Int) -> Bool {
        unlockedTrophies[TrophyID(category: category, tierIndex: tier).storageKey] != nil
    }

    private var highestUnlockedTier: Int? {
        (0..<8).reversed().first { isUnlocked($0) }
    }

    private var nextTierIndex: Int? {
        let next = (highestUnlockedTier ?? -1) + 1
        return next < category.thresholds.count ? next : nil
    }

    private var tierAlertMessage: String {
        guard let tier = selectedTier else { return "" }
        let threshold = category.thresholds[tier]
        if let date = unlockedTrophies[TrophyID(category: category, tierIndex: tier).storageKey] {
            return "Obtenu le \(date.formatted(date: .abbreviated, time: .omitted)) — seuil : \(threshold)\(category.unitSuffix)"
        } else {
            return "À débloquer : \(threshold)\(category.unitSuffix)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.icon).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline).foregroundStyle(.primary)
                    Text("\(currentValue)\(category.unitSuffix)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { tier in
                    Circle()
                        .fill(isUnlocked(tier) ? Color(hex: TrophyTier.colorHex[tier]) : Color(.tertiarySystemFill))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(isUnlocked(tier) ? Color.clear : Color(.separator), lineWidth: 1)
                        )
                        .onTapGesture { selectedTier = tier }
                }
            }

            if let next = nextTierIndex {
                let threshold = category.thresholds[next]
                let previous  = next > 0 ? category.thresholds[next - 1] : 0
                let progress  = threshold > previous
                    ? min(1.0, max(0.0, Double(currentValue - previous) / Double(threshold - previous)))
                    : 0
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("Prochain palier : \(TrophyTier.names[next]) à \(threshold)\(category.unitSuffix)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Tous les paliers obtenus 🏆")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert(
            selectedTier.map { TrophyTier.names[$0] } ?? "",
            isPresented: Binding(
                get: { selectedTier != nil },
                set: { if !$0 { selectedTier = nil } }
            )
        ) {
            Button("OK", role: .cancel) { selectedTier = nil }
        } message: {
            Text(tierAlertMessage)
        }
    }
}

private extension Color {
    init(hex: String) {
        var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexValue.removeAll { $0 == "#" }
        var rgb: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&rgb)
        self.init(red: Double((rgb & 0xFF0000) >> 16) / 255,
                  green: Double((rgb & 0x00FF00) >> 8) / 255,
                  blue: Double(rgb & 0x0000FF) / 255)
    }
}
