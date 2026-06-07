import ConnectIQ
import CoreBluetooth

class GarminManager: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate, CBCentralManagerDelegate {
    static let shared = GarminManager()

    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!
    // CoreBluetooth UUID de la Forerunner 255 (trouvé via LightBlue)
    private let watchPeripheralUUID = UUID(uuidString: "41336F81-A64C-B864-E5F7-CB128CA064B8")!
    private let store = SessionStore.shared
    private let sdk = ConnectIQ.sharedInstance()!
    private var central: CBCentralManager?

    @Published var lastSyncDate: Date? = nil
    @Published var connectedDevice: IQDevice? = nil
    @Published var lastSlotSendMessage: String? = nil

    func setup() {
        sdk.initialize(withUrlScheme: "baskettrainer", uiOverrideDelegate: nil)
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            tryRegisterWatch(central)
        }
    }

    private func tryRegisterWatch(_ central: CBCentralManager) {
        if let p = central.retrievePeripherals(withIdentifiers: [watchPeripheralUUID]).first {
            registerIQDevice(peripheralUUID: p.identifier, name: "Forerunner 255")
            return
        }
        let garminService = CBUUID(string: "6A4E8022-667B-11E3-949A-0800200C9A66")
        for p in central.retrieveConnectedPeripherals(withServices: [garminService]) {
            registerIQDevice(peripheralUUID: p.identifier, name: p.name ?? "Forerunner 255")
        }
    }

    private func registerIQDevice(peripheralUUID: UUID, name: String) {
        guard let device = IQDevice(id: peripheralUUID, modelName: "fr255", friendlyName: name) else { return }
        sdk.register(forDeviceEvents: device, delegate: self)
    }

    func connectWatch() {
        if let c = central, c.state == .poweredOn {
            tryRegisterWatch(c)
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let devices = sdk.parseDeviceSelectionResponse(from: url) as? [IQDevice],
              !devices.isEmpty else { return }
        for device in devices {
            sdk.register(forDeviceEvents: device, delegate: self)
        }
    }

    // MARK: - IQDeviceEventDelegate

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        if status == .connected {
            connectedDevice = device
            let app = IQApp(uuid: appUUID, store: appUUID, device: device)
            sdk.register(forAppMessages: app, delegate: self)
            // Réveille l'app montre → BasketApp.onStart() → SyncManager.flush()
            sdk.openAppRequest(app) { _ in }
        } else if connectedDevice?.uuid == device.uuid {
            connectedDevice = nil
        }
    }

    // MARK: - IQAppMessageDelegate

    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        parseAndStore(dict)
    }

    private func parseAndStore(_ dict: [String: Any]) {
        let exId       = dict["exerciseId"] as? Int ?? 0
        let total      = dict["totalShots"] as? Int ?? 0
        let made       = dict["madeShots"]  as? Int ?? 0
        let startTime  = dict["startTime"]  as? Int ?? 0
        let duration   = dict["duration"]   as? Int ?? 0
        let rawResults = dict["results"] as? [Bool] ?? []
        let targetMade = dict["targetMade"] as? Int
        let shotTypeId = dict["shotTypeId"] as? Int

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots: total,
            madeShots: made,
            results: rawResults,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration = TimeInterval(duration)
        session.sentFromWatch = true
        if let stId = shotTypeId, let st = ShotType(rawValue: stId) {
            session.shotType = st
        }

        // Si targetMade présent, créer une série simple avec l'objectif
        if let target = targetMade {
            var series = ShotSeries(exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
                                    totalShots: total, madeShots: made, results: rawResults)
            series.targetMade = target
            session.series = [series]
        }

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.store.add(session)
        }
    }

    func sendSlot(_ index: Int, template: ComplexTemplate) {
        guard let device = connectedDevice else {
            lastSlotSendMessage = "Montre non connectée"
            return
        }
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        let payload: [String: Any] = [
            "type": "slot",
            "index": index,
            "series": template.series.map {
                [
                    "exerciseId": $0.exerciseType.rawValue,
                    "totalShots": $0.totalShots,
                    "shotTypeId": $0.shotType.rawValue
                ]
            }
        ]
        // Réveille l'app montre avant d'envoyer — sendMessage exige que l'app
        // cible soit active sur la montre pour recevoir le message (cf. le
        // même besoin déjà rencontré pour la sync au moment de la connexion).
        sdk.openAppRequest(app) { [weak self] _ in
            self?.sdk.sendMessage(payload, to: app, progress: nil) { result in
                print("sendSlot(\(index)) → \(NSStringFromSendMessageResult(result))")
                DispatchQueue.main.async {
                    self?.lastSlotSendMessage = result == .success
                        ? "Entraînement \(index + 1) envoyé à la montre ✅"
                        : "Échec de l'envoi : \(NSStringFromSendMessageResult(result))"
                }
            }
        }
    }

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}
