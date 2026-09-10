import Foundation

enum TrophyEngine {
    static func longestRun(_ results: [Bool]) -> Int {
        var best = 0, current = 0
        for made in results {
            current = made ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    static func longestConsecutiveDayRun(_ days: Set<Date>, cal: Calendar) -> Int {
        var best = 0, current = 0
        var previous: Date? = nil
        for day in days.sorted() {
            if let prev = previous, cal.isDate(cal.date(byAdding: .day, value: 1, to: prev)!, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }
}

struct TrophyProgress {
    let unlocks: [TrophyID: Date]
    let currentValues: [TrophyCategory: Int]
}

extension TrophyEngine {
    static func evaluate(sessions: [WorkoutSession]) -> TrophyProgress {
        var unlocked: [TrophyID: Date] = [:]
        let cal = Calendar.current

        var totalShots = 0
        var byCategory: [String: Int] = [:]
        var sessionCount = 0
        var bestAccuracyPct = 0
        var bestMakeStreak = 0
        var trainingDays: Set<Date> = []

        func record(_ category: TrophyCategory, _ value: Int, _ date: Date) {
            for (i, threshold) in category.thresholds.enumerated() {
                let id = TrophyID(category: category, tierIndex: i)
                if value >= threshold && unlocked[id] == nil {
                    unlocked[id] = date
                }
            }
        }

        let volumeCategories: [TrophyCategory] = [.freeThrowVolume, .threePointVolume, .midRangeVolume, .techniqueVolume]

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            sessionCount += 1
            trainingDays.insert(cal.startOfDay(for: session.date))

            for segment in session.shotSegments {
                totalShots += segment.totalShots
                byCategory[segment.exerciseType.category, default: 0] += segment.totalShots
                if segment.totalShots >= 15 {
                    let pct = Int((Double(segment.results.filter { $0 }.count) / Double(segment.totalShots) * 100).rounded())
                    bestAccuracyPct = max(bestAccuracyPct, pct)
                }
                bestMakeStreak = max(bestMakeStreak, longestRun(segment.results))
            }

            record(.totalShots, totalShots, session.date)
            for category in volumeCategories {
                record(category, byCategory[category.exerciseCategoryFilter!] ?? 0, session.date)
            }
            record(.sessionCount, sessionCount, session.date)
            record(.streakDays, longestConsecutiveDayRun(trainingDays, cal: cal), session.date)
            record(.bestAccuracy, bestAccuracyPct, session.date)
            record(.makeStreak, bestMakeStreak, session.date)
        }

        let currentValues: [TrophyCategory: Int] = [
            .totalShots:       totalShots,
            .freeThrowVolume:  byCategory["Lancer Franc"] ?? 0,
            .threePointVolume: byCategory["3 Points"] ?? 0,
            .midRangeVolume:   byCategory["Mi-distance"] ?? 0,
            .techniqueVolume:  byCategory["Technique"] ?? 0,
            .sessionCount:     sessionCount,
            .streakDays:       longestConsecutiveDayRun(trainingDays, cal: cal),
            .bestAccuracy:     bestAccuracyPct,
            .makeStreak:       bestMakeStreak,
        ]

        return TrophyProgress(unlocks: unlocked, currentValues: currentValues)
    }
}
