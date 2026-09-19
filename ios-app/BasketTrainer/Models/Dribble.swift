import Foundation

// ─────────────────────────────────────────────────
// ROUTINES DE DRIBBLE — modèles purs (aucune dépendance UI)
// ─────────────────────────────────────────────────

struct DribbleStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var drill: String?        // nil = repos
    var seconds: Int

    var isRest: Bool { drill == nil }
}

struct DribbleRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var steps: [DribbleStep]

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
}

struct DribbleDrillTime: Codable, Equatable {
    var drill: String
    var seconds: Int
}

struct DribbleSession: Codable, Identifiable {
    var id = UUID()
    var routineName: String
    var date: Date                    // heure de départ ; (date, routineName) dédoublonne les renvois montre
    var totalSeconds: Int
    var drillTimes: [DribbleDrillTime]
    var sentFromWatch: Bool
}

enum DribbleLibrary {
    static let builtInDrills = [
        "Cross", "Behind the back", "In and out", "Between the legs",
        "Crossover", "Hesitation", "Double cross", "Pound dribble",
    ]
    static let maxSteps = 20
    static let stepSecondsRange = 5...600
    static let maxDrillNameLength = 30

    // Résout un nom saisi par l'utilisateur : nil si vide, le nom canonique existant
    // (comparaison insensible à la casse) s'il est déjà connu, sinon le nom nettoyé
    // marqué `isNew`.
    static func resolveDrill(_ raw: String, known: [String]) -> (name: String, isNew: Bool)? {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxDrillNameLength))
        guard !trimmed.isEmpty else { return nil }
        if let match = known.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return (match, false)
        }
        return (trimmed, true)
    }
}

enum DribbleFormat {
    // "45 s", "1 min", "1 min 30 s"
    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    // "m:ss"
    static func clock(_ seconds: Int) -> String {
        let t = max(seconds, 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
