import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE — Persistence des séances (UserDefaults)
// Source unique de vérité pour toutes les vues
// ─────────────────────────────────────────────────

class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions:   [WorkoutSession]   = []
    @Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: maxWatchSlots)
    @Published private(set) var spotPositionOverrides: [ExerciseType: SpotPosition] = [:]

    private let storageKey   = "basket_sessions"
    private let slotsKey     = "basket_watch_slots"
    private let spotPositionsKey = "basket_spot_positions"

    static let maxWatchSlots = 5

    init() {
        load()
        loadSlots()
        loadSpotPositions()
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

    func spotStats(for exerciseType: ExerciseType) -> SpotStats {
        spotStats(for: exerciseType, in: sessions)
    }

    func spotStats(for exerciseType: ExerciseType, in sessions: [WorkoutSession]) -> SpotStats {
        var totalShots = 0
        var totalMade  = 0
        var byType: [ShotType: (shots: Int, made: Int)] = [:]

        for session in sessions {
            if let seriesList = session.series {
                for s in seriesList where s.exerciseType == exerciseType {
                    totalShots += s.totalShots
                    totalMade  += s.madeShots
                    if let t = s.shotType {
                        var e = byType[t] ?? (shots: 0, made: 0)
                        e.shots += s.totalShots
                        e.made  += s.madeShots
                        byType[t] = e
                    }
                }
            } else if session.exerciseType == exerciseType {
                totalShots += session.totalShots
                totalMade  += session.madeShots
                if let t = session.shotType {
                    var e = byType[t] ?? (shots: 0, made: 0)
                    e.shots += session.totalShots
                    e.made  += session.madeShots
                    byType[t] = e
                }
            }
        }

        return SpotStats(exerciseType: exerciseType,
                         totalShots: totalShots,
                         totalMade: totalMade,
                         byType: byType)
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

    // ── Watch Slots ──

    func setWatchSlot(_ index: Int, template: ComplexTemplate?) {
        guard index >= 0 && index < Self.maxWatchSlots else { return }
        watchSlots[index] = template
        saveSlots()
    }

    private func saveSlots() {
        if let data = try? JSONEncoder().encode(watchSlots) {
            UserDefaults.standard.set(data, forKey: slotsKey)
        }
    }

    private func loadSlots() {
        guard let data = UserDefaults.standard.data(forKey: slotsKey),
              let decoded = try? JSONDecoder().decode([ComplexTemplate?].self, from: data),
              decoded.count == Self.maxWatchSlots
        else { return }
        watchSlots = decoded
    }

    // ── Spot Positions ──

    func setSpotPosition(_ type: ExerciseType, nx: CGFloat, ny: CGFloat) {
        spotPositionOverrides[type] = SpotPosition(nx: nx, ny: ny)
        saveSpotPositions()
    }

    func resetSpotPositions(for types: [ExerciseType]) {
        for type in types {
            spotPositionOverrides.removeValue(forKey: type)
        }
        saveSpotPositions()
    }

    private func saveSpotPositions() {
        let wire = Dictionary(uniqueKeysWithValues:
            spotPositionOverrides.map { (key, value) in (key.rawValue, value) })
        if let data = try? JSONEncoder().encode(wire) {
            UserDefaults.standard.set(data, forKey: spotPositionsKey)
        }
    }

    private func loadSpotPositions() {
        guard let data = UserDefaults.standard.data(forKey: spotPositionsKey),
              let decoded = try? JSONDecoder().decode([Int: SpotPosition].self, from: data)
        else { return }
        var result: [ExerciseType: SpotPosition] = [:]
        for (rawValue, position) in decoded {
            if let type = ExerciseType(rawValue: rawValue) {
                result[type] = position
            }
        }
        spotPositionOverrides = result
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
