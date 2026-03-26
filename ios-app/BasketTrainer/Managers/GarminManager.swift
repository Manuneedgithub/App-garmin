import Foundation
import Combine
import ConnectIQ

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Communication bidirectionnelle
// Réception via CIQ SDK (transmit depuis montre) ← primary
// Réception via URL scheme (openWebPage)          ← fallback
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    @Published var lastSyncDate: Date? = nil

    // ── Mode guidé ──
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex:    Int = 0
    @Published var guidedSeries:   [ShotSeries] = []

    private let store   = SessionStore.shared
    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!

    // ── Init SDK ──
    func setup() {
        ConnectIQ.sharedInstance().initialize(
            urlScheme: "baskettrainer",
            store: IQAppStore.delegating
        )
        ConnectIQ.sharedInstance().register(forDeviceEvents: .all, delegate: self)
        print("[GarminManager] CIQ SDK initialisé — en attente de la montre")
    }

    // ── Mode guidé ──

    func startGuidedSession(_ template: ComplexTemplate) {
        guidedTemplate = template
        guidedIndex    = 0
        guidedSeries   = []
    }

    func cancelGuidedSession() {
        guidedTemplate = nil
        guidedIndex    = 0
        guidedSeries   = []
    }

    // ── URL entrante depuis Garmin Connect (SDK + fallback URL scheme) ──
    func handleIncomingURL(_ url: URL) {
        // Le SDK CIQ utilise notre URL scheme pour sa propre communication
        ConnectIQ.sharedInstance().parseIncoming(from: url)

        // Fallback : URL directe baskettrainer://s?... (openWebPage)
        guard url.scheme == "baskettrainer",
              url.host == "s",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        var exerciseId = 0, totalShots = 0, madeShots = 0, startTime = 0
        var results = [Bool]()
        for item in queryItems {
            switch item.name {
            case "e": exerciseId = Int(item.value ?? "") ?? 0
            case "t": totalShots = Int(item.value ?? "") ?? 0
            case "m": madeShots  = Int(item.value ?? "") ?? 0
            case "s": startTime  = Int(item.value ?? "") ?? 0
            case "r": results    = (item.value ?? "").map { $0 == "1" }
            default: break
            }
        }
        let dict: [String: Any] = [
            "exerciseId": exerciseId, "totalShots": totalShots,
            "madeShots": madeShots,  "startTime":  startTime,
            "results":   results
        ]
        DispatchQueue.main.async { self.processSessionData(dict) }
    }

    // ── Traitement commun d'une session reçue ──
    private func processSessionData(_ data: [String: Any]) {
        lastSyncDate = Date()

        // Payload multi-séries envoyé depuis MultiSummaryDelegate (SessionAccumulator)
        if let isMulti = data["isMulti"] as? Bool, isMulti,
           let seriesArr = data["series"] as? [[String: Any]] {
            let series = seriesArr.map { ShotSeries(fromGarmin: $0) }
            let ts     = data["startTime"] as? Int ?? 0
            var session = WorkoutSession.makeComplex(
                series: series,
                date:   Date(timeIntervalSince1970: TimeInterval(ts))
            )
            session.duration      = (data["duration"] as? Int).map { TimeInterval($0) }
            session.sentFromWatch = true
            store.add(session)
            return
        }

        // Payload simple — mode guidé ou séance unique
        if let template = guidedTemplate {
            let ser = ShotSeries(fromGarmin: data)
            guidedSeries.append(ser)
            guidedIndex += 1

            if guidedIndex >= template.series.count {
                let ts = data["startTime"] as? Int ?? 0
                var session = WorkoutSession.makeComplex(
                    series: guidedSeries,
                    date:   Date(timeIntervalSince1970: TimeInterval(ts))
                )
                session.sentFromWatch = true
                store.add(session)
                guidedTemplate = nil; guidedIndex = 0; guidedSeries = []
            }
        } else {
            store.add(WorkoutSession(fromGarmin: data))
        }
    }

    func sendWorkoutConfig(exerciseId: Int, totalShots: Int) {
        // Non supporté sans le Store CIQ — la config se fait sur la montre
    }

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}

// ─────────────────────────────────────────────────
// IQDeviceEventDelegate — détection automatique de la montre
// ─────────────────────────────────────────────────
extension GarminManager: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        print("[GarminManager] Montre \(device.friendlyName ?? "?") — statut: \(status.rawValue)")
        guard status == .connected else { return }

        // Enregistrement pour recevoir les messages de notre app sur cette montre
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
        print("[GarminManager] En écoute des messages transmit() de la montre")
    }
}

// ─────────────────────────────────────────────────
// IQAppMessageDelegate — réception des données transmit()
// ─────────────────────────────────────────────────
extension GarminManager: IQAppMessageDelegate {
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        print("[GarminManager] Message reçu: \(String(describing: message))")
        guard let data = message as? [String: Any] else { return }
        DispatchQueue.main.async { self.processSessionData(data) }
    }
}
