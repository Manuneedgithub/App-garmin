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

enum ShotType: Int, CaseIterable, Codable {
    case catchAndShoot = 0
    case offDribble    = 1
    case standing      = 2

    var name: String {
        switch self {
        case .catchAndShoot: return "Catch & Shoot"
        case .offDribble:    return "Avec dribble"
        case .standing:      return "À l'arrêt"
        }
    }
}

// Résultat d'un tir individuel
struct ShotResult: Codable {
    let made: Bool
}

// ─────────────────────────────────────────────────
// Série de tirs (pour les séances complexes)
// ─────────────────────────────────────────────────
struct ShotSeries: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseType: ExerciseType
    var totalShots: Int
    var madeShots: Int
    var results: [Bool]
    var targetMade: Int?   // objectif paniers (nil si mode tirs libres)
    var shotType: ShotType?   // nil = données historiques sans type

    var percentage: Double { totalShots == 0 ? 0 : Double(madeShots) / Double(totalShots) * 100 }
    var missedShots: Int { totalShots - madeShots }

    init(exerciseType: ExerciseType, totalShots: Int, madeShots: Int, results: [Bool] = []) {
        self.exerciseType = exerciseType
        self.totalShots   = totalShots
        self.madeShots    = madeShots
        self.results      = results
    }

    // Depuis les données d'une série envoyée par la montre (dans un payload multi)
    init(fromGarmin data: [String: Any]) {
        let exId = data["exerciseId"] as? Int ?? 0
        self.exerciseType = ExerciseType(rawValue: exId) ?? .freethrow
        self.totalShots   = data["totalShots"] as? Int ?? 0
        self.madeShots    = data["madeShots"]  as? Int ?? 0
        self.results      = (data["results"] as? [Bool]) ?? []
        self.targetMade   = data["targetMade"] as? Int
        if let stId = data["shotTypeId"] as? Int {
            self.shotType = ShotType(rawValue: stId)
        } else {
            self.shotType = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseType, totalShots, madeShots, results, targetMade, shotType
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self,         forKey: .id) ?? UUID()
        exerciseType = try c.decode(ExerciseType.self,          forKey: .exerciseType)
        totalShots   = try c.decode(Int.self,                   forKey: .totalShots)
        madeShots    = try c.decode(Int.self,                   forKey: .madeShots)
        results      = try c.decodeIfPresent([Bool].self,       forKey: .results) ?? []
        targetMade   = try c.decodeIfPresent(Int.self,          forKey: .targetMade)
        shotType     = try c.decodeIfPresent(ShotType.self,     forKey: .shotType)
    }
}

// ─────────────────────────────────────────────────
// Une séance complète d'entraînement
// ─────────────────────────────────────────────────
struct WorkoutSession: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseType: ExerciseType      // type principal (1ère série pour les complexes)
    var totalShots: Int
    var madeShots: Int
    var results: [Bool]                  // true = réussi, false = raté
    var date: Date
    var sentFromWatch: Bool              // true si reçu depuis la montre Garmin
    var series: [ShotSeries]?            // nil = séance simple, non-nil = séance complexe
    var duration: TimeInterval?          // durée en secondes (nil si non tracée)
    var shotType: ShotType?   // for simple sessions (no series array)

    // ── Propriétés calculées ──

    var isComplex: Bool { (series?.count ?? 0) > 1 }

    var displayName: String {
        if let s = series, s.count > 1 { return "Séance complexe (\(s.count) séries)" }
        return exerciseType.name
    }

    var displayEmoji: String { isComplex ? "🗂️" : exerciseType.emoji }

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

    // ── Constructeurs ──

    // Depuis les données reçues de la montre
    init(fromGarmin data: [String: Any]) {
        let exId = data["exerciseId"] as? Int ?? 0
        exerciseType  = ExerciseType(rawValue: exId) ?? .freethrow
        totalShots    = data["totalShots"] as? Int ?? 0
        madeShots     = data["madeShots"]  as? Int ?? 0
        results       = (data["results"] as? [Bool]) ?? []
        date          = Date(timeIntervalSince1970: TimeInterval(data["startTime"] as? Int ?? 0))
        sentFromWatch = true
        series        = nil
        duration      = (data["duration"] as? Int).map { TimeInterval($0) }
        if let stId = data["shotTypeId"] as? Int {
            shotType = ShotType(rawValue: stId)
        } else {
            shotType = nil
        }
    }

    // Constructeur manuel simple (ajout depuis l'iPhone)
    init(exerciseType: ExerciseType, totalShots: Int, madeShots: Int,
         results: [Bool] = [], date: Date = Date()) {
        self.exerciseType  = exerciseType
        self.totalShots    = totalShots
        self.madeShots     = madeShots
        self.results       = results
        self.date          = date
        self.sentFromWatch = false
        self.series        = nil
        self.duration      = nil
        self.shotType      = nil
    }

    // Constructeur séance complexe (plusieurs séries)
    static func makeComplex(series: [ShotSeries], date: Date = Date()) -> WorkoutSession {
        let total   = series.reduce(0) { $0 + $1.totalShots }
        let made    = series.reduce(0) { $0 + $1.madeShots }
        let results = series.flatMap { $0.results }
        var s = WorkoutSession(
            exerciseType: series.first?.exerciseType ?? .freethrow,
            totalShots: total,
            madeShots: made,
            results: results
        )
        s.date     = date
        s.series   = series
        s.duration = nil
        s.shotType = nil
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseType, totalShots, madeShots, results, date,
             sentFromWatch, series, duration, shotType
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,           forKey: .id) ?? UUID()
        exerciseType  = try c.decode(ExerciseType.self,            forKey: .exerciseType)
        totalShots    = try c.decode(Int.self,                     forKey: .totalShots)
        madeShots     = try c.decode(Int.self,                     forKey: .madeShots)
        results       = try c.decodeIfPresent([Bool].self,         forKey: .results) ?? []
        date          = try c.decodeIfPresent(Date.self,           forKey: .date) ?? Date()
        sentFromWatch = try c.decodeIfPresent(Bool.self,           forKey: .sentFromWatch) ?? false
        series        = try c.decodeIfPresent([ShotSeries].self,   forKey: .series)
        duration      = try c.decodeIfPresent(TimeInterval.self,   forKey: .duration)
        shotType      = try c.decodeIfPresent(ShotType.self,       forKey: .shotType)
    }
}

// ─────────────────────────────────────────────────
// Templates de séance complexe (max 5)
// ─────────────────────────────────────────────────

struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int
    var targetMade: Int?
    var shotType: ShotType = .catchAndShoot

    private enum CodingKeys: String, CodingKey {
        case exerciseType, totalShots, targetMade, shotType
    }

    init(exerciseType: ExerciseType, totalShots: Int,
         targetMade: Int? = nil, shotType: ShotType = .catchAndShoot) {
        self.exerciseType = exerciseType
        self.totalShots   = totalShots
        self.targetMade   = targetMade
        self.shotType     = shotType
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        exerciseType = try c.decode(ExerciseType.self,      forKey: .exerciseType)
        totalShots   = try c.decode(Int.self,               forKey: .totalShots)
        targetMade   = try c.decodeIfPresent(Int.self,      forKey: .targetMade)
        shotType     = try c.decodeIfPresent(ShotType.self, forKey: .shotType) ?? .catchAndShoot
    }
}

struct ComplexTemplate: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var series: [TemplateSeries]
    var createdAt: Date = Date()
}

// ─────────────────────────────────────────────────
// Statistiques agrégées par exercice
// (gère les séances complexes via series)
// ─────────────────────────────────────────────────
struct ExerciseStats {
    let exerciseType: ExerciseType
    let sessions: [WorkoutSession]

    var totalSessions: Int { sessions.count }

    var totalShots: Int {
        sessions.reduce(0) { acc, s in
            if let series = s.series {
                return acc + series.filter { $0.exerciseType == exerciseType }
                                   .reduce(0) { $0 + $1.totalShots }
            }
            return acc + s.totalShots
        }
    }

    var totalMade: Int {
        sessions.reduce(0) { acc, s in
            if let series = s.series {
                return acc + series.filter { $0.exerciseType == exerciseType }
                                   .reduce(0) { $0 + $1.madeShots }
            }
            return acc + s.madeShots
        }
    }

    var avgPercentage: Double {
        guard totalShots > 0 else { return 0 }
        return Double(totalMade) / Double(totalShots) * 100
    }

    var bestSession: WorkoutSession? { sessions.max(by: { $0.percentage < $1.percentage }) }
}

struct SpotStats {
    let exerciseType: ExerciseType
    let totalShots: Int
    let totalMade: Int
    var percentage: Double {
        totalShots == 0 ? 0 : Double(totalMade) / Double(totalShots) * 100
    }
    let byType: [ShotType: (shots: Int, made: Int)]
}

// ─────────────────────────────────────────────────
// Position personnalisée d'un repère sur le terrain
// (coordonnées normalisées, même convention que CourtSpot :
// nx/ny = fraction du rectangle du terrain depuis bas-gauche)
// ─────────────────────────────────────────────────
struct SpotPosition: Codable {
    var nx: CGFloat
    var ny: CGFloat
}
