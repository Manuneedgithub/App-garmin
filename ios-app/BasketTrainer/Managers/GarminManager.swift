import ConnectIQ
import Foundation
import Combine

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Communication Bluetooth native
// via le SDK officiel Connect IQ (SPM)
// Données reçues automatiquement, sans confirmation utilisateur
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    private let appUUID      = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!
    private let deviceCacheKey = "garmin_cached_device"

    @Published var isConnected:   Bool = false
    @Published var isDeviceSetup: Bool = false

    private var device: IQDevice?
    private var iqApp:  IQApp?
    private let store = SessionStore.shared

    // ── Initialisation au lancement ──
    func setup() {
        ConnectIQ.sharedInstance().initialize(withUrlScheme: "baskettrainer",
                                              uiOverrideDelegate: nil)
        restoreCachedDevice()
    }

    // ── Ouvre Garmin Connect pour choisir la montre (setup 1 fois) ──
    func selectDevice() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    // ── Appelé depuis onOpenURL quand Garmin Connect renvoie vers l'app ──
    func handleIncomingURL(_ url: URL) {
        guard let devices = ConnectIQ.sharedInstance()
                .parseDeviceSelectionResponse(from: url) as? [IQDevice],
              let first = devices.first else { return }
        configure(device: first)
        cacheDevice(first)
    }

    // ── Simulation — ajoute une séance de test ──
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

    // ── Envoi config vers montre (optionnel) ──
    func sendWorkoutConfig(exerciseId: Int, totalShots: Int) {
        guard let app = iqApp else { return }
        let payload: [String: Any] = ["exerciseId": exerciseId, "totalShots": totalShots]
        ConnectIQ.sharedInstance().sendMessage(payload, to: app, progress: nil) { _ in }
    }

    // ─────────────────────────────────────────────────
    // PRIVATE
    // ─────────────────────────────────────────────────

    private func configure(device: IQDevice) {
        if self.device != nil {
            ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
            ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
        }
        self.device = device
        self.iqApp  = IQApp(uuid: appUUID, store: appUUID, device: device)

        ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
        ConnectIQ.sharedInstance().register(forAppMessages: iqApp!, delegate: self)

        DispatchQueue.main.async { self.isDeviceSetup = true }
    }

    private func cacheDevice(_ device: IQDevice) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: device,
                                                         requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: deviceCacheKey)
        }
    }

    private func restoreCachedDevice() {
        guard let data = UserDefaults.standard.data(forKey: deviceCacheKey),
              let device = try? NSKeyedUnarchiver.unarchivedObject(ofClass: IQDevice.self,
                                                                    from: data)
        else { return }
        configure(device: device)
    }
}

// ─────────────────────────────────────────────────
// DELEGATES SDK
// ─────────────────────────────────────────────────

extension GarminManager: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        DispatchQueue.main.async {
            self.isConnected = (status == .connected)
        }
    }
}

extension GarminManager: IQAppMessageDelegate {
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        let session = WorkoutSession(fromGarmin: dict)
        DispatchQueue.main.async {
            self.store.add(session)
        }
    }
}
