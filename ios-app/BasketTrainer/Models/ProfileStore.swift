import Foundation
import Combine

class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profile: UserProfile? = nil

    private let storageKey = "basket_user_profile"
    private var cancellable: AnyCancellable?

    init() {
        load()
        cancellable = SessionStore.shared.$sessions
            .dropFirst()
            .sink { [weak self] sessions in
                self?.refreshStatsSummary(from: sessions)
            }
    }

    // ── Écriture ──

    func save(_ draft: UserProfile) {
        var toSave = draft
        toSave.statsSummary = Self.computeStatsSummary(from: SessionStore.shared.sessions)
        profile = toSave
        persist()
    }

    private func refreshStatsSummary(from sessions: [WorkoutSession]) {
        guard var updated = profile else { return }
        updated.statsSummary = Self.computeStatsSummary(from: sessions)
        profile = updated
        persist()
    }

    // ── Calcul des stats ──

    private static func computeStatsSummary(from sessions: [WorkoutSession]) -> ProfileStatsSummary {
        var totalShots = 0, madeShots = 0
        var byCategory: [String: (shots: Int, made: Int)] = [:]
        for session in sessions {
            for segment in session.shotSegments {
                totalShots += segment.totalShots
                madeShots  += segment.madeShots
                var entry = byCategory[segment.exerciseType.category] ?? (0, 0)
                entry.shots += segment.totalShots
                entry.made  += segment.madeShots
                byCategory[segment.exerciseType.category] = entry
            }
        }
        let categories = ["Lancer Franc", "3 Points", "Mi-distance", "Technique"]
        let zones = categories.map { cat -> ZoneStat in
            let entry = byCategory[cat] ?? (0, 0)
            return ZoneStat(category: cat, shots: entry.shots, made: entry.made)
        }
        return ProfileStatsSummary(
            totalSessions: sessions.count,
            totalShots: totalShots,
            overallFGPercentage: totalShots == 0 ? 0 : Double(madeShots) / Double(totalShots) * 100,
            longestStreak: longestStreak(from: sessions),
            zonePerformance: zones
        )
    }

    private static func longestStreak(from sessions: [WorkoutSession]) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, current = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev {
                let next = cal.date(byAdding: .day, value: 1, to: p)!
                current = cal.isDate(next, inSameDayAs: d) ? current + 1 : 1
            } else {
                current = 1
            }
            best = max(best, current)
            prev = d
        }
        return best
    }

    // ── Persistence ──

    private func persist() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(UserProfile?.self, from: data)
        else { return }
        profile = decoded
    }
}
