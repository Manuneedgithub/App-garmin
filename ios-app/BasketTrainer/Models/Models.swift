import Foundation

// ─────────────────────────────────────────────────
// MODÈLES DE DONNÉES
// ─────────────────────────────────────────────────

// Types d'exercices (même ordre que la montre)
enum ExerciseType: Int, CaseIterable, Codable, Identifiable {
    case freethrow      = 0
    case threeCenter    = 1
    case threeRight45   = 2
    case threeLeft45    = 3
    case threeCornerR   = 4
    case threeCornerL   = 5
    case midCenter      = 6
    case midRight       = 7
    case midLeft        = 8

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .freethrow:    return "Lancer Franc"
        case .threeCenter:  return "3pts Centre"
        case .threeRight45: return "3pts 45° Droite"
        case .threeLeft45:  return "3pts 45° Gauche"
        case .threeCornerR: return "3pts Coin Droite"
        case .threeCornerL: return "3pts Coin Gauche"
        case .midCenter:    return "Mi-distance Centre"
        case .midRight:     return "Mi-distance Droite"
        case .midLeft:      return "Mi-distance Gauche"
        }
    }

    var emoji: String {
        switch self {
        case .freethrow:                        return "🎯"
        case .threeCenter:                      return "🏀"
        case .threeRight45, .threeLeft45:       return "↗️"
        case .threeCornerR, .threeCornerL:      return "📐"
        case .midCenter, .midRight, .midLeft:   return "🎳"
        }
    }

    // Catégorie pour regrouper dans les stats
    var category: String {
        switch self {
        case .freethrow:                        return "Lancer Franc"
        case .threeCenter, .threeRight45,
             .threeLeft45, .threeCornerR,
             .threeCornerL:                     return "3 Points"
        case .midCenter, .midRight, .midLeft:   return "Mi-distance"
        }
    }
}

// Résultat d'un tir individuel
struct ShotResult: Codable {
    let made: Bool
}

// Une séance complète d'entraînement
struct WorkoutSession: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseType: ExerciseType
    var totalShots: Int
    var madeShots: Int
    var results: [Bool]          // true = réussi, false = raté
    var date: Date
    var sentFromWatch: Bool      // true si reçu depuis la montre Garmin

    var missedShots: Int { totalShots - madeShots }
    var percentage: Double { totalShots == 0 ? 0 : Double(madeShots) / Double(totalShots) * 100 }

    // Appréciation textuelle de la performance
    var performanceLabel: String {
        switch percentage {
        case 85...: return "Excellent"
        case 70...: return "Très bien"
        case 55...: return "Bien"
        case 40...: return "À améliorer"
        default:    return "Difficile"
        }
    }

    var performanceColor: String {
        switch percentage {
        case 85...: return "green"
        case 70...: return "orange"
        case 55...: return "yellow"
        default:    return "red"
        }
    }

    // Constructeur depuis les données reçues de la montre
    init(fromGarmin data: [String: Any]) {
        let exId = data["exerciseId"] as? Int ?? 0
        exerciseType = ExerciseType(rawValue: exId) ?? .freethrow
        totalShots   = data["totalShots"] as? Int ?? 0
        madeShots    = data["madeShots"]  as? Int ?? 0
        results      = (data["results"] as? [Bool]) ?? []
        date         = Date(timeIntervalSince1970: TimeInterval(data["startTime"] as? Int ?? 0))
        sentFromWatch = true
    }

    // Constructeur manuel (ajout depuis l'iPhone)
    init(exerciseType: ExerciseType, totalShots: Int, madeShots: Int, results: [Bool]) {
        self.exerciseType = exerciseType
        self.totalShots   = totalShots
        self.madeShots    = madeShots
        self.results      = results
        self.date         = Date()
        self.sentFromWatch = false
    }
}

// Statistiques agrégées par exercice
struct ExerciseStats {
    let exerciseType: ExerciseType
    let sessions: [WorkoutSession]

    var totalSessions: Int   { sessions.count }
    var totalShots: Int      { sessions.reduce(0) { $0 + $1.totalShots } }
    var totalMade: Int       { sessions.reduce(0) { $0 + $1.madeShots } }
    var avgPercentage: Double {
        guard totalShots > 0 else { return 0 }
        return Double(totalMade) / Double(totalShots) * 100
    }
    var bestSession: WorkoutSession? { sessions.max(by: { $0.percentage < $1.percentage }) }
}
