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
