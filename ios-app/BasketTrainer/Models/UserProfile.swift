import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case homme, femme, autre
    var id: String { rawValue }
    var label: String {
        switch self {
        case .homme: return "Homme"
        case .femme: return "Femme"
        case .autre: return "Autre"
        }
    }
}

enum PlayerPosition: String, Codable, CaseIterable, Identifiable {
    case meneur, arriere, ailier, ailierFort, pivot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .meneur:     return "Meneur"
        case .arriere:    return "Arrière"
        case .ailier:     return "Ailier"
        case .ailierFort: return "Ailier fort"
        case .pivot:      return "Pivot"
        }
    }
}

struct ZoneStat: Codable, Identifiable {
    var category: String   // "Lancer Franc" / "3 Points" / "Mi-distance" / "Technique"
    var shots: Int
    var made: Int
    var id: String { category }
    var percentage: Double { shots == 0 ? 0 : Double(made) / Double(shots) * 100 }
}

struct ProfileStatsSummary: Codable {
    var totalSessions: Int
    var totalShots: Int
    var overallFGPercentage: Double
    var longestStreak: Int
    var zonePerformance: [ZoneStat]

    static let empty = ProfileStatsSummary(totalSessions: 0, totalShots: 0,
                                            overallFGPercentage: 0, longestStreak: 0,
                                            zonePerformance: [])
}

struct UserProfile: Codable {
    var username: String
    var age: Int?
    var sex: Sex?
    var position: PlayerPosition?
    var heightCm: Int?
    var weightKg: Int?
    var photoData: Data?
    var statsSummary: ProfileStatsSummary
}
