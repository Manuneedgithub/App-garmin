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

        // MARK: - Task 2: WorkoutSession.shotSegments

        let simple = WorkoutSession(exerciseType: .freethrow, totalShots: 10, madeShots: 7,
                                     results: [true, true, true, true, true, true, true, false, false, false])
        assert(simple.shotSegments.count == 1)
        assert(simple.shotSegments[0].exerciseType == .freethrow)
        assert(simple.shotSegments[0].totalShots == 10)
        assert(simple.shotSegments[0].results.count == 10)

        var complex = WorkoutSession(exerciseType: .freethrow, totalShots: 999, madeShots: 999, results: [])
        complex.series = [
            ShotSeries(exerciseType: .freethrow, totalShots: 5, madeShots: 3, results: [true, true, true, false, false]),
            ShotSeries(exerciseType: .threeCenter, totalShots: 8, madeShots: 4,
                       results: [true, false, true, false, true, false, true, false])
        ]
        assert(complex.shotSegments.count == 2, "must read from series, not the placeholder top-level fields")
        assert(complex.shotSegments[0].exerciseType == .freethrow)
        assert(complex.shotSegments[0].totalShots == 5)
        assert(complex.shotSegments[1].exerciseType == .threeCenter)
        assert(complex.shotSegments[1].totalShots == 8)

        print("Task 2 assertions passed")

        // MARK: - Task 3: TrophyEngine pure helpers

        assert(TrophyEngine.longestRun([]) == 0)
        assert(TrophyEngine.longestRun([false, false]) == 0)
        assert(TrophyEngine.longestRun([true, true, true]) == 3)
        assert(TrophyEngine.longestRun([true, false, true, true, false, true, true, true]) == 3)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        func testDay(_ day: Int) -> Date {
            utcCal.date(from: DateComponents(year: 2026, month: 1, day: day))!
        }
        let scatteredDays: Set<Date> = [testDay(1), testDay(2), testDay(3), testDay(5), testDay(8), testDay(9)]
        assert(TrophyEngine.longestConsecutiveDayRun(scatteredDays, cal: utcCal) == 3)
        assert(TrophyEngine.longestConsecutiveDayRun([], cal: utcCal) == 0)
        assert(TrophyEngine.longestConsecutiveDayRun([testDay(1)], cal: utcCal) == 1)

        print("Task 3 assertions passed")
    }
}
