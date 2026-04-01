import ConnectIQ

class GarminManager: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate {
    static let shared = GarminManager()

    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!
    private let store = SessionStore.shared
    private let sdk = ConnectIQ.sharedInstance()!

    @Published var lastSyncDate: Date? = nil
    @Published var connectedDevice: IQDevice? = nil

    // Guided session properties
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex: Int = 0
    @Published var guidedSeries: [ShotSeries] = []

    func setup() {
        sdk.initialize(withUrlScheme: "baskettrainer", uiOverrideDelegate: nil)
    }

    // Called by BasketTrainerApp.onOpenURL
    // Garmin Connect wakes the app via "baskettrainer://..." to provide the device list
    func handleIncomingURL(_ url: URL) {
        guard let devices = sdk.parseDeviceSelectionResponseFromURL(url) as? [IQDevice],
              !devices.isEmpty else { return }
        for device in devices {
            sdk.register(forDeviceEvents: device, delegate: self)
        }
    }

    // IQDeviceEventDelegate — watch connection/disconnection
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        if status == .connected {
            connectedDevice = device
            let app = IQApp.appWithUUID(appUUID, storeUuid: appUUID, device: device)
            sdk.register(forAppMessages: app, delegate: self)
        } else {
            connectedDevice = nil
        }
    }

    // IQAppMessageDelegate — message received from watch
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

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots: total,
            madeShots: made,
            results: rawResults,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration = TimeInterval(duration)
        session.sentFromWatch = true

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.handleSessionOrGuided(session, results: rawResults, total: total, made: made)
        }
    }

    private func handleSessionOrGuided(
        _ session: WorkoutSession, results: [Bool], total: Int, made: Int
    ) {
        if let template = guidedTemplate {
            let ser = ShotSeries(
                exerciseType: session.exerciseType,
                totalShots: total, madeShots: made, results: results
            )
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
