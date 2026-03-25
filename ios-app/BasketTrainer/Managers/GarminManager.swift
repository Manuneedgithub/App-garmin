import Foundation
import Combine

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Pont entre l'iPhone et la montre
//
// Ce fichier utilise le Garmin Connect IQ Mobile SDK.
// Une fois le SDK installé (voir SETUP.md) :
//   1. Remplace "import Foundation" par "import ConnectIQ"
//   2. Décommente les blocs SDK marqués // [SDK]
//   3. Supprime les blocs mock marqués  // [MOCK]
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    // UUID de ton app Garmin (= même UUID que dans manifest.xml)
    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!

    @Published var isConnected: Bool = false
    @Published var lastError: String?

    private let store = SessionStore.shared

    // ── Initialisation SDK ──
    override init() {
        super.init()
        // [SDK] ConnectIQ.sharedInstance().initialize(withUrlScheme: "baskettrainer", uiOverrideDelegate: nil)
        // [SDK] ConnectIQ.sharedInstance().register(forDeviceEvents: self, as: self)
    }

    // Appelé au lancement de l'app (depuis AppDelegate ou App struct)
    func setup() {
        // [SDK] ConnectIQ.sharedInstance().findDevices()
        print("[GarminManager] Setup — SDK non encore intégré, mode simulation actif")
    }

    // ── Réception de données depuis la montre ──
    // [SDK] Implémente IQAppMessageDelegate.receivedMessage

    func handleIncomingMessage(_ message: Any) {
        guard let dict = message as? [String: Any] else { return }
        let session = WorkoutSession(fromGarmin: dict)
        DispatchQueue.main.async {
            self.store.add(session)
        }
    }

    // ── Envoi de config vers la montre ──
    func sendWorkoutConfig(exerciseId: Int, totalShots: Int) {
        let payload: [String: Any] = [
            "exerciseId": exerciseId,
            "totalShots": totalShots
        ]
        // [SDK] device?.sendMessage(payload, progress: nil, completion: nil)
        print("[GarminManager] Envoi config → montre : \(payload)")
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

// ─────────────────────────────────────────────────
// GUIDE D'INTÉGRATION SDK (résumé)
//
// 1. Télécharge ConnectIQ.xcframework sur developer.garmin.com
// 2. Glisse-le dans Xcode > Frameworks, Libraries, Embedded Content
// 3. Ajoute dans Info.plist :
//      LSApplicationQueriesSchemes → ["com.garmin.connect.mobile"]
//      CFBundleURLTypes → scheme "baskettrainer" (deep link retour)
// 4. Dans AppDelegate.application(_:open:) :
//      ConnectIQ.sharedInstance().parseIncoming(url)
// 5. Décommente les blocs // [SDK] dans ce fichier
// ─────────────────────────────────────────────────
