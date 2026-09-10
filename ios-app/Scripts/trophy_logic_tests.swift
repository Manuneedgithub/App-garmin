import Foundation

// MARK: - Task 1: TrophyCategory & TrophyTier & TrophyID

@main
struct TrophyTests {
    static func main() {
        for category in TrophyCategory.allCases {
            assert(category.thresholds.count == 8, "\(category) must have exactly 8 tiers")
        }

        assert(TrophyTier.names.count == 8)
        assert(TrophyTier.colorHex.count == 8)
        assert(TrophyCategory.totalShots.thresholds == [100, 250, 500, 1000, 2000, 3500, 5000, 10000])
        assert(TrophyCategory.sessionCount.thresholds == [5, 15, 30, 50, 100, 200, 350, 500])
        assert(TrophyCategory.streakDays.thresholds == [3, 5, 7, 14, 21, 30, 60, 100])
        assert(TrophyCategory.bestAccuracy.thresholds == [50, 60, 70, 80, 85, 90, 95, 100])
        assert(TrophyCategory.makeStreak.thresholds == [5, 10, 15, 20, 30, 40, 50, 75])
        assert(TrophyCategory.bestAccuracy.unitSuffix == "%")
        assert(TrophyCategory.totalShots.unitSuffix == "")
        assert(TrophyCategory.freeThrowVolume.exerciseCategoryFilter == "Lancer Franc")
        assert(TrophyCategory.threePointVolume.exerciseCategoryFilter == "3 Points")
        assert(TrophyCategory.midRangeVolume.exerciseCategoryFilter == "Mi-distance")
        assert(TrophyCategory.techniqueVolume.exerciseCategoryFilter == "Technique")
        assert(TrophyCategory.totalShots.exerciseCategoryFilter == nil)
        assert(TrophyCategory.sessionCount.exerciseCategoryFilter == nil)

        let id = TrophyID(category: .streakDays, tierIndex: 3)
        assert(id.storageKey == "streakDays_3")
        let roundTripped = TrophyID(storageKey: "streakDays_3")
        assert(roundTripped?.category == .streakDays)
        assert(roundTripped?.tierIndex == 3)
        assert(TrophyID(storageKey: "not_a_real_key_at_all") == nil)
        assert(TrophyID(storageKey: "totalShots_0")?.category == .totalShots)

        print("Task 1 assertions passed")
    }
}
