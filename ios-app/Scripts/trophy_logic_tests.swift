import Foundation

// MARK: - Task 1: TrophyCategory & TrophyTier & TrophyID

@main
struct TrophyTests {
    static func main() {
        for category in TrophyCategory.allCases {
            precondition(category.thresholds.count == 8, "\(category) must have exactly 8 tiers")
        }

        precondition(TrophyTier.names.count == 8)
        precondition(TrophyTier.colorHex.count == 8)
        precondition(TrophyCategory.totalShots.thresholds == [100, 250, 500, 1000, 2000, 3500, 5000, 10000])
        precondition(TrophyCategory.sessionCount.thresholds == [5, 15, 30, 50, 100, 200, 350, 500])
        precondition(TrophyCategory.streakDays.thresholds == [3, 5, 7, 14, 21, 30, 60, 100])
        precondition(TrophyCategory.bestAccuracy.thresholds == [50, 60, 70, 80, 85, 90, 95, 100])
        precondition(TrophyCategory.makeStreak.thresholds == [5, 10, 15, 20, 30, 40, 50, 75])
        precondition(TrophyCategory.bestAccuracy.unitSuffix == "%")
        precondition(TrophyCategory.totalShots.unitSuffix == "")
        precondition(TrophyCategory.freeThrowVolume.exerciseCategoryFilter == "Lancer Franc")
        precondition(TrophyCategory.threePointVolume.exerciseCategoryFilter == "3 Points")
        precondition(TrophyCategory.midRangeVolume.exerciseCategoryFilter == "Mi-distance")
        precondition(TrophyCategory.techniqueVolume.exerciseCategoryFilter == "Technique")
        precondition(TrophyCategory.totalShots.exerciseCategoryFilter == nil)
        precondition(TrophyCategory.sessionCount.exerciseCategoryFilter == nil)

        let id = TrophyID(category: .streakDays, tierIndex: 3)
        precondition(id.storageKey == "streakDays_3")
        let roundTripped = TrophyID(storageKey: "streakDays_3")
        precondition(roundTripped?.category == .streakDays)
        precondition(roundTripped?.tierIndex == 3)
        precondition(TrophyID(storageKey: "not_a_real_key_at_all") == nil)
        precondition(TrophyID(storageKey: "totalShots_0")?.category == .totalShots)

        print("Task 1 assertions passed")

        // MARK: - Task 2: WorkoutSession.shotSegments

        let simple = WorkoutSession(exerciseType: .freethrow, totalShots: 10, madeShots: 7,
                                     results: [true, true, true, true, true, true, true, false, false, false])
        precondition(simple.shotSegments.count == 1)
        precondition(simple.shotSegments[0].exerciseType == .freethrow)
        precondition(simple.shotSegments[0].totalShots == 10)
        precondition(simple.shotSegments[0].results.count == 10)

        var complex = WorkoutSession(exerciseType: .freethrow, totalShots: 999, madeShots: 999, results: [])
        complex.series = [
            ShotSeries(exerciseType: .freethrow, totalShots: 5, madeShots: 3, results: [true, true, true, false, false]),
            ShotSeries(exerciseType: .threeCenter, totalShots: 8, madeShots: 4,
                       results: [true, false, true, false, true, false, true, false])
        ]
        precondition(complex.shotSegments.count == 2, "must read from series, not the placeholder top-level fields")
        precondition(complex.shotSegments[0].exerciseType == .freethrow)
        precondition(complex.shotSegments[0].totalShots == 5)
        precondition(complex.shotSegments[1].exerciseType == .threeCenter)
        precondition(complex.shotSegments[1].totalShots == 8)

        print("Task 2 assertions passed")

        // MARK: - Task 3: TrophyEngine pure helpers

        precondition(TrophyEngine.longestRun([]) == 0)
        precondition(TrophyEngine.longestRun([false, false]) == 0)
        precondition(TrophyEngine.longestRun([true, true, true]) == 3)
        precondition(TrophyEngine.longestRun([true, false, true, true, false, true, true, true]) == 3)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        func testDay(_ day: Int) -> Date {
            utcCal.date(from: DateComponents(year: 2026, month: 1, day: day))!
        }
        let scatteredDays: Set<Date> = [testDay(1), testDay(2), testDay(3), testDay(5), testDay(8), testDay(9)]
        precondition(TrophyEngine.longestConsecutiveDayRun(scatteredDays, cal: utcCal) == 3)
        precondition(TrophyEngine.longestConsecutiveDayRun([], cal: utcCal) == 0)
        precondition(TrophyEngine.longestConsecutiveDayRun([testDay(1)], cal: utcCal) == 1)

        print("Task 3 assertions passed")

        // MARK: - Task 4: TrophyEngine.evaluate

        func date2026(_ month: Int, _ day: Int) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = month; c.day = day; c.hour = 12
            return Calendar(identifier: .gregorian).date(from: c)!
        }

        // (a) Out-of-order input still resolves chronologically, and tiers are
        //     attributed to the session that actually crossed them (first-crossing-wins).
        let sessionB = WorkoutSession(exerciseType: .freethrow, totalShots: 150, madeShots: 100,
                                       results: Array(repeating: true, count: 100) + Array(repeating: false, count: 50),
                                       date: date2026(2, 1))   // pushes total to 300 -> crosses tier1 (250)
        let sessionA = WorkoutSession(exerciseType: .freethrow, totalShots: 150, madeShots: 90,
                                       results: Array(repeating: true, count: 90) + Array(repeating: false, count: 60),
                                       date: date2026(1, 1))   // pushes total to 150 -> crosses tier0 (100) only

        let progress = TrophyEngine.evaluate(sessions: [sessionB, sessionA])   // deliberately reversed order
        let tier0 = TrophyID(category: .totalShots, tierIndex: 0)
        let tier1 = TrophyID(category: .totalShots, tierIndex: 1)
        precondition(progress.unlocks[tier0] == date2026(1, 1), "tier0 (100) must be dated to sessionA, the one that actually crossed it")
        precondition(progress.unlocks[tier1] == date2026(2, 1), "tier1 (250) must be dated to sessionB, not overwritten back to sessionA")
        precondition(progress.currentValues[.totalShots] == 300)

        // (b) Category isolation: an all-freethrow history must not unlock 3pt volume tiers.
        let freeThrowOnlyTier0 = TrophyID(category: .freeThrowVolume, tierIndex: 0)
        let threePointTier0    = TrophyID(category: .threePointVolume, tierIndex: 0)
        precondition(progress.unlocks[freeThrowOnlyTier0] != nil)
        precondition(progress.unlocks[threePointTier0] == nil)
        precondition(progress.currentValues[.threePointVolume] == 0)

        // (c) bestAccuracy ignores segments under 15 shots; makeStreak does not cross segment boundaries.
        //     Evaluated on complexSession alone: its 10-shot series (100%, <15 shots) must be excluded from
        //     bestAccuracy, and its 20-shot series' 60% must be the answer; the two series' streaks must not merge.
        var complexSession = WorkoutSession(exerciseType: .freethrow, totalShots: 0, madeShots: 0, results: [], date: date2026(3, 1))
        complexSession.series = [
            ShotSeries(exerciseType: .freethrow, totalShots: 10, madeShots: 10,
                       results: Array(repeating: true, count: 10)),               // 100% but only 10 shots -> ignored for bestAccuracy
            ShotSeries(exerciseType: .threeCenter, totalShots: 20, madeShots: 12,
                       results: [true,true,true,true, false, true,true,true,true, false,
                                 true,true,true,true, false,false,false,false,false,false])  // 12/20 = 60%, longest run = 4
        ]
        let progress2 = TrophyEngine.evaluate(sessions: [complexSession])
        precondition(progress2.currentValues[.bestAccuracy] == 60, "the 10-shot 100% segment must not count (< 15 shots)")
        precondition(progress2.currentValues[.makeStreak] == 10, "longest run is the 10-shot all-makes segment; must not merge with the second series")

        // (d) sessionCount tier crossing at exact threshold.
        var fiveSessions: [WorkoutSession] = []
        for i in 1...5 {
            fiveSessions.append(WorkoutSession(exerciseType: .freethrow, totalShots: 1, madeShots: 1,
                                                results: [true], date: date2026(4, i)))
        }
        let progress3 = TrophyEngine.evaluate(sessions: fiveSessions)
        precondition(progress3.unlocks[TrophyID(category: .sessionCount, tierIndex: 0)] == date2026(4, 5))

        print("Task 4 assertions passed")
    }
}
