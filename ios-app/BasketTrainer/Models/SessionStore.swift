import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE — Persistence des séances (UserDefaults)
// Source unique de vérité pour toutes les vues
// ─────────────────────────────────────────────────

class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [WorkoutSession] = []

    private let storageKey = "basket_sessions"

    init() {
        load()
    }

    // ── Lecture ──

    var recentSessions: [WorkoutSession] {
        sessions.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }

    func sessions(for type: ExerciseType) -> [WorkoutSession] {
        sessions.filter { s in
            if let series = s.series {
                return series.contains { $0.exerciseType == type }
            }
            return s.exerciseType == type
        }.sorted { $0.date > $1.date }
    }

    func stats(for type: ExerciseType) -> ExerciseStats {
        ExerciseStats(exerciseType: type, sessions: sessions(for: type))
    }

    // Calcule les stats sur un sous-ensemble de séances (pour le filtre temporel)
    func allStats(from src: [WorkoutSession]) -> [ExerciseStats] {
        ExerciseType.allCases
            .map { type -> ExerciseStats in
                let matching = src.filter { s in
                    if let series = s.series {
                        return series.contains { $0.exerciseType == type }
                    }
                    return s.exerciseType == type
                }
                return ExerciseStats(exerciseType: type, sessions: matching)
            }
            .filter { $0.totalSessions > 0 }
            .sorted { $0.avgPercentage > $1.avgPercentage }
    }

    func allStats() -> [ExerciseStats] { allStats(from: sessions) }

    var totalSessions: Int { sessions.count }
    var totalShots: Int    { sessions.reduce(0) { $0 + $1.totalShots } }
    var overallPct: Double {
        let made  = sessions.reduce(0) { $0 + $1.madeShots }
        let total = totalShots
        return total == 0 ? 0 : Double(made) / Double(total) * 100
    }

    // ── Écriture ──

    func add(_ session: WorkoutSession) {
        sessions.append(session)
        save()
    }

    func update(_ session: WorkoutSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        let sorted = sessions.sorted { $0.date > $1.date }
        offsets.forEach { idx in
            if let i = sessions.firstIndex(where: { $0.id == sorted[idx].id }) {
                sessions.remove(at: i)
            }
        }
        save()
    }

    func deleteSession(_ session: WorkoutSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    // ── Persistence ──

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data)
        else { return }
        sessions = decoded
    }
}
