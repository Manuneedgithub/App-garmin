import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE DRIBBLE — routines, exercices perso, emplacements montre, historique.
// Même conventions que ProfileStore/SessionStore (UserDefaults + Codable).
// ─────────────────────────────────────────────────
final class DribbleStore: ObservableObject {
    static let shared = DribbleStore()
    static let watchSlotCount = 5

    @Published private(set) var routines: [DribbleRoutine] = []
    @Published private(set) var customDrills: [String] = []
    @Published private(set) var watchSlots: [DribbleRoutine?] = Array(repeating: nil, count: DribbleStore.watchSlotCount)
    @Published private(set) var sessions: [DribbleSession] = []

    private let routinesKey     = "basket_dribble_routines"
    private let customDrillsKey = "basket_dribble_custom_drills"
    private let watchSlotsKey   = "basket_dribble_watch_slots"
    private let sessionsKey     = "basket_dribble_sessions"

    init() {
        if let v: [DribbleRoutine] = load(routinesKey) { routines = v }
        if let v: [String] = load(customDrillsKey) { customDrills = v }
        if let v: [DribbleRoutine?] = load(watchSlotsKey), v.count == Self.watchSlotCount { watchSlots = v }
        if let v: [DribbleSession] = load(sessionsKey) { sessions = v }
    }

    var allDrills: [String] { DribbleLibrary.builtInDrills + customDrills }

    // ── Routines ──

    func save(_ routine: DribbleRoutine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[i] = routine
        } else {
            routines.append(routine)
        }
        persist(routines, routinesKey)
    }

    func delete(_ routine: DribbleRoutine) {
        routines.removeAll { $0.id == routine.id }
        persist(routines, routinesKey)
    }

    // ── Exercices ──

    // Nom canonique d'un exercice saisi (nil si vide). Enregistre un nouvel exercice perso au besoin.
    func resolveDrill(_ raw: String) -> String? {
        guard let resolved = DribbleLibrary.resolveDrill(raw, known: allDrills) else { return nil }
        if resolved.isNew {
            customDrills.append(resolved.name)
            persist(customDrills, customDrillsKey)
        }
        return resolved.name
    }

    // ── Emplacements montre (copie de la routine au moment de l'envoi) ──

    func setWatchSlot(_ index: Int, routine: DribbleRoutine?) {
        guard watchSlots.indices.contains(index) else { return }
        watchSlots[index] = routine
        persist(watchSlots, watchSlotsKey)
    }

    // ── Historique ──

    @discardableResult
    func add(_ session: DribbleSession) -> Bool {
        // La montre peut renvoyer une séance déjà livrée (callback de fin perdu) — on l'ignore.
        if sessions.contains(where: { $0.date == session.date && $0.routineName == session.routineName }) {
            return false
        }
        sessions.append(session)
        persist(sessions, sessionsKey)
        return true
    }

    func deleteSession(_ session: DribbleSession) {
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
