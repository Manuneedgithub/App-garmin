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

    // Guided session properties
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex: Int = 0
    @Published var guidedSeries: [ShotSeries] = []

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

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots: total,
            madeShots: made,
            results: rawResults,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration = TimeInterval(duration)
        session.sentFromWatch = true

        // Si targetMade présent, créer une série simple avec l'objectif
        if let target = targetMade {
            var series = ShotSeries(exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
                                    totalShots: total, madeShots: made, results: rawResults)
            series.targetMade = target
            session.series = [series]
        }

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.handleSessionOrGuided(session, results: rawResults, total: total, made: made)
        }
    }

    private func handleSessionOrGuided(_ session: WorkoutSession, results: [Bool], total: Int, made: Int) {
        if let template = guidedTemplate {
            let ser = ShotSeries(exerciseType: session.exerciseType, totalShots: total, madeShots: made, results: results)
            guidedSeries.append(ser)
            guidedIndex += 1
            if guidedIndex >= template.series.count {
                var complex = WorkoutSession.makeComplex(series: guidedSeries, date: session.date)
                complex.sentFromWatch = true
                store.add(complex)
                cancelGuidedSession()
            }
        } else {
            store.add(session)
        }
    }

    func startGuidedSession(_ template: ComplexTemplate) {
        guidedTemplate = template; guidedIndex = 0; guidedSeries = []
    }

    func cancelGuidedSession() {
        guidedTemplate = nil; guidedIndex = 0; guidedSeries = []
    }

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}
