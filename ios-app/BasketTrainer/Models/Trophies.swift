import Foundation

enum TrophyCategory: String, Codable, CaseIterable, Identifiable {
    case totalShots, freeThrowVolume, threePointVolume, midRangeVolume
    case techniqueVolume, sessionCount, streakDays, bestAccuracy, makeStreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalShots:       return "Volume total"
        case .freeThrowVolume:  return "Lancer Franc"
        case .threePointVolume: return "3 Points"
        case .midRangeVolume:   return "Mi-distance"
        case .techniqueVolume:  return "Technique"
        case .sessionCount:     return "Séances jouées"
        case .streakDays:       return "Régularité"
        case .bestAccuracy:     return "Meilleure séance"
        case .makeStreak:       return "Série de réussites"
        }
    }

    var icon: String {
        switch self {
        case .totalShots:                     return "🏀"
        case .freeThrowVolume, .bestAccuracy: return "🎯"
        case .threePointVolume:               return "🏹"
        case .midRangeVolume:                 return "🎳"
        case .techniqueVolume:                return "↔️"
        case .sessionCount:                   return "📅"
        case .streakDays:                     return "🔥"
        case .makeStreak:                     return "⚡"
        }
    }

    var thresholds: [Int] {
        switch self {
        case .totalShots, .freeThrowVolume, .threePointVolume,
             .midRangeVolume, .techniqueVolume:
            return [100, 250, 500, 1000, 2000, 3500, 5000, 10000]
        case .sessionCount:  return [5, 15, 30, 50, 100, 200, 350, 500]
        case .streakDays:    return [3, 5, 7, 14, 21, 30, 60, 100]
        case .bestAccuracy:  return [50, 60, 70, 80, 85, 90, 95, 100]
        case .makeStreak:    return [5, 10, 15, 20, 30, 40, 50, 75]
        }
    }

    var unitSuffix: String { self == .bestAccuracy ? "%" : "" }

    var exerciseCategoryFilter: String? {
        switch self {
        case .freeThrowVolume:  return "Lancer Franc"
        case .threePointVolume: return "3 Points"
        case .midRangeVolume:   return "Mi-distance"
        case .techniqueVolume:  return "Technique"
        default: return nil
        }
    }
}

enum TrophyTier {
    static let names: [String] = ["Bronze", "Argent", "Or", "Platine", "Diamant", "Maître", "Champion", "Légende"]
    static let colorHex: [String] = ["#CD7F32", "#C0C0C0", "#FFD700", "#B9C6D6",
                                      "#8CD9E0", "#7C5CD9", "#FF6600", "#FF3B8D"]
}

struct TrophyID: Hashable {
    let category: TrophyCategory
    let tierIndex: Int   // 0...7

    var storageKey: String { "\(category.rawValue)_\(tierIndex)" }

    init(category: TrophyCategory, tierIndex: Int) {
        self.category = category
        self.tierIndex = tierIndex
    }

    // Reconstructs a TrophyID from a persisted key like "streakDays_3".
    init?(storageKey: String) {
        guard let underscoreIndex = storageKey.lastIndex(of: "_"),
              let tier = Int(storageKey[storageKey.index(after: underscoreIndex)...]),
              let category = TrophyCategory(rawValue: String(storageKey[storageKey.startIndex..<underscoreIndex]))
        else { return nil }
        self.category = category
        self.tierIndex = tier
    }
}
