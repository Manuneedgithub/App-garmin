import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE EXERCICES PHYSIQUES — bibliothèque, emplacements montre, historique.
// Mêmes conventions que DribbleStore/ProfileStore (UserDefaults + Codable).
// ─────────────────────────────────────────────────
final class PhysicalStore: ObservableObject {
    static let shared = PhysicalStore()
    static let watchSlotCount = 5

    @Published private(set) var exercises: [PhysicalExercise] = []
    @Published private(set) var watchSlots: [PhysicalExercise?] = Array(repeating: nil, count: PhysicalStore.watchSlotCount)
    @Published private(set) var sessions: [PhysicalSession] = []

    private let exercisesKey  = "basket_physical_exercises"
    private let watchSlotsKey = "basket_physical_watch_slots"
    private let sessionsKey   = "basket_physical_sessions"

    init() {
        if let v: [PhysicalExercise] = load(exercisesKey) {
            exercises = v
        } else {
            exercises = PhysicalLibrary.builtIn   // premier lancement : pas de valeur stockée encore
        }
        if let v: [PhysicalExercise?] = load(watchSlotsKey), v.count == Self.watchSlotCount { watchSlots = v }
        if let v: [PhysicalSession] = load(sessionsKey) { sessions = v }
    }

    // ── Exercices ──

    func save(_ exercise: PhysicalExercise) {
        if let i = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[i] = exercise
        } else {
            exercises.append(exercise)
        }
        persist(exercises, exercisesKey)
    }

    func delete(_ exercise: PhysicalExercise) {
        exercises.removeAll { $0.id == exercise.id }
        persist(exercises, exercisesKey)
    }

    // ── Emplacements montre (copie de l'exercice au moment de l'envoi) ──

    func setWatchSlot(_ index: Int, exercise: PhysicalExercise?) {
        guard watchSlots.indices.contains(index) else { return }
        watchSlots[index] = exercise
        persist(watchSlots, watchSlotsKey)
    }

    // ── Historique ──

    @discardableResult
    func add(_ session: PhysicalSession) -> Bool {
        // La montre peut renvoyer une séance déjà livrée (callback de fin perdu) — on l'ignore.
        if sessions.contains(where: { $0.date == session.date && $0.exerciseName == session.exerciseName }) {
            return false
        }
        sessions.append(session)
        persist(sessions, sessionsKey)
        return true
    }

    func deleteSession(_ session: PhysicalSession) {
        sessions.removeAll { $0.id == session.id }
        persist(sessions, sessionsKey)
    }

    // ── Persistence ──

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
