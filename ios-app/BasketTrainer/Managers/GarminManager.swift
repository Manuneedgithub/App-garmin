import Foundation
import Combine

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Reçoit les sessions via URL scheme
// baskettrainer://s?e=0&t=10&m=7&s=1234567890&r=1101001010
// Envoyé par la montre via Communications.openWebPage()
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    @Published var isConnected: Bool = false

    private let store = SessionStore.shared

    func setup() {
        print("[GarminManager] Prêt — en attente URL baskettrainer://")
    }

    // ── Appelé depuis BasketTrainerApp quand Garmin Connect renvoie l'URL ──
    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "baskettrainer",
              url.host == "s",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        var exerciseId = 0
        var totalShots = 0
        var madeShots  = 0
        var startTime  = 0
        var results    = [Bool]()

        for item in queryItems {
            switch item.name {
            case "e": exerciseId = Int(item.value ?? "") ?? 0
            case "t": totalShots = Int(item.value ?? "") ?? 0
            case "m": madeShots  = Int(item.value ?? "") ?? 0
            case "s": startTime  = Int(item.value ?? "") ?? 0
            case "r": results    = (item.value ?? "").map { $0 == "1" }
            default:  break
            }
        }

        let dict: [String: Any] = [
            "exerciseId": exerciseId,
            "totalShots": totalShots,
            "madeShots":  madeShots,
            "startTime":  startTime,
            "results":    results
        ]

        let session = WorkoutSession(fromGarmin: dict)
        DispatchQueue.main.async {
            self.store.add(session)
            self.isConnected = true
        }
    }

    // ── Envoi config vers montre (non utilisé avec URL scheme) ──
    func sendWorkoutConfig(exerciseId: Int, totalShots: Int) {
        print("[GarminManager] sendWorkoutConfig ignoré en mode URL scheme")
    }

    // ── Simulation ──
    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        let made    = results.filter { $0 }.count
        let session = WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots:   10,
            madeShots:    made,
            results:      results
        )
        store.add(session)
    }
}
