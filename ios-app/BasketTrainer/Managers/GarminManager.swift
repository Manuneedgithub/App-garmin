import Foundation
import Combine

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Réception via URL scheme
// La montre envoie baskettrainer://s?... via openWebPage()
// iOS reçoit via onOpenURL → handleIncomingURL()
// Pas de ConnectIQ SDK nécessaire
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject {
    static let shared = GarminManager()

    @Published var lastSyncDate: Date? = nil
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex:    Int = 0
    @Published var guidedSeries:   [ShotSeries] = []

    private let store = SessionStore.shared

    func setup() {
        print("[GarminManager] Prêt — en attente URL baskettrainer://")
    }

    // ── URL entrante depuis la montre (via openWebPage) ──
    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "baskettrainer" else { return }

        if url.host == "s" {
            handleSimpleSession(url)
        } else if url.host == "m" {
            handleMultiSession(url)
        }
    }

    // ── Séance simple : baskettrainer://s?e=0&t=10&m=7&st=...&r=1101...&d=180 ──
    private func handleSimpleSession(_ url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        var p = [String: String]()
        items.forEach { p[$0.name] = $0.value }

        let exId      = Int(p["e"] ?? "0") ?? 0
        let total     = Int(p["t"] ?? "0") ?? 0
        let made      = Int(p["m"] ?? "0") ?? 0
        let startTime = Int(p["st"] ?? "0") ?? 0
        let duration  = Int(p["d"] ?? "0") ?? 0
        let results   = (p["r"] ?? "").map { $0 == "1" }

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots: total, madeShots: made, results: results,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration      = TimeInterval(duration)
        session.sentFromWatch = true

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            if let template = self.guidedTemplate {
                let ser = ShotSeries(exerciseType: session.exerciseType,
                                     totalShots: total, madeShots: made, results: results)
                self.guidedSeries.append(ser)
                self.guidedIndex += 1
                if self.guidedIndex >= template.series.count {
                    var complex = WorkoutSession.makeComplex(series: self.guidedSeries,
                                                             date: session.date)
                    complex.sentFromWatch = true
                    self.store.add(complex)
                    self.cancelGuidedSession()
                }
            } else {
                self.store.add(session)
            }
        }
    }

    // ── Séance multi : baskettrainer://m?st=...&d=...&n=2&s0e=0&s0t=10... ──
    private func handleMultiSession(_ url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        var p = [String: String]()
        items.forEach { p[$0.name] = $0.value }

        let n         = Int(p["n"] ?? "0") ?? 0
        let startTime = Int(p["st"] ?? "0") ?? 0
        let duration  = Int(p["d"] ?? "0") ?? 0

        var series = [ShotSeries]()
        for i in 0..<n {
            let exId    = Int(p["s\(i)e"] ?? "0") ?? 0
            let total   = Int(p["s\(i)t"] ?? "0") ?? 0
            let made    = Int(p["s\(i)m"] ?? "0") ?? 0
            let results = (p["s\(i)r"] ?? "").map { $0 == "1" }
            series.append(ShotSeries(exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
                                     totalShots: total, madeShots: made, results: results))
        }

        var session = WorkoutSession.makeComplex(
            series: series,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration      = TimeInterval(duration)
        session.sentFromWatch = true

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.store.add(session)
        }
    }

    // ── Mode guidé ──
    func startGuidedSession(_ template: ComplexTemplate) {
        guidedTemplate = template; guidedIndex = 0; guidedSeries = []
    }

    func cancelGuidedSession() {
        guidedTemplate = nil; guidedIndex = 0; guidedSeries = []
    }

    // ── Bouton connexion (non nécessaire avec openWebPage) ──
    func showDeviceSelection() {
        // openWebPage() ne nécessite pas de sélection de device
        // La montre envoie directement via Garmin Connect
    }

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}
