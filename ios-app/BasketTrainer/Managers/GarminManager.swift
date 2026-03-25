import Foundation
import Combine

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Reçoit les données de la montre
// via URL scheme baskettrainer://s?e=0&t=10&m=7&s=...&r=1101001010
// La montre envoie l'URL via Communications.openWebPage()
// Garmin Connect la transfère automatiquement à cette app
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    @Published var isConnected: Bool = false
    @Published var lastError: String?

    private let store = SessionStore.shared

    func setup() {
        print("[GarminManager] Prêt — en attente URL baskettrainer://")
    }

    // ── Appelé depuis BasketTrainerApp quand l'URL baskettrainer:// arrive ──
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

    // ── Envoi config vers la montre (non utilisé avec URL scheme) ──
    func sendWorkoutConfig(exerciseId: Int, totalShots: Int) {
        print("[GarminManager] Config ignorée — communication montre→iPhone uniquement")
    }

    // ── Simulation — ajoute une fausse séance pour tester l'UI ──
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
