# Trophy System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an 8-track, 8-tier achievement system to the iPhone app, computed from full session history, persisted once unlocked, and browsable in a new "Trophées" tab with a celebration popup on new unlocks.

**Architecture:** Two new dependency-free model files (`Trophies.swift` for the static catalog of categories/tiers, `TrophyEngine.swift` for the pure history-replay algorithm) feed a small amount of new state on the existing `SessionStore` singleton (`unlockedTrophies` persisted dict + `pendingCelebrations` queue). Two new SwiftUI views (`TrophiesView`, `CelebrationOverlayView`) read that state; `ContentView` wires in the new tab and the overlay.

**Tech Stack:** Swift 5 / SwiftUI, `UserDefaults` + `JSONEncoder`/`JSONDecoder` for persistence (matching every other store in `SessionStore`), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-08-trophy-system-design.md`

## Global Constraints

- iOS app only — no watch-side code, no sync to the Garmin device.
- Exactly 8 tracks: `totalShots`, `freeThrowVolume`, `threePointVolume`, `midRangeVolume`, `techniqueVolume`, `sessionCount`, `streakDays`, `bestAccuracy`, `makeStreak`.
- Exactly 8 tiers per track, named (index 0→7): Bronze, Argent, Or, Platine, Diamant, Maître, Champion, Légende.
- Thresholds are fixed per the spec's table (repeated in Task 1) — do not invent different numbers.
- Once a tier is recorded as unlocked it is **never** removed, even if the sessions that earned it are later deleted.
- `bestAccuracy` only considers a session/series segment with `totalShots >= 15`.
- `makeStreak` (longest run of consecutive makes) is computed **per segment** (one session, or one series within a complex session) — never concatenated across segments.
- The very first evaluation ever run (inside `SessionStore.init()`) must backfill silently — no celebration popups for trophies that were already earned before this feature existed.
- New tab is named "Trophées" with SF Symbol `trophy.fill`, placed between Stats and Terrain.
- This project has **no Xcode test target** (confirmed: no `.xctestplan`, no unit-test bundle in `project.pbxproj`, no `.xcscheme` files at all — Xcode generates a scheme on the fly). Pure logic (no SwiftUI/UIKit) is verified via `swiftc`-compiled command-line scripts against the real source files (no duplicated logic). Anything touching SwiftUI or `UserDefaults`-backed `SessionStore` behavior is verified by building for iOS Simulator and a manual pass — call this out explicitly in each such task, don't skip it.
- This project also has no shared Xcode scheme, so build-verification commands use `-target BasketTrainer`, not `-scheme BasketTrainer`.

---

### Task 1: Trophy catalog (`TrophyCategory`, `TrophyTier`, `TrophyID`)

**Files:**
- Create: `ios-app/BasketTrainer/Models/Trophies.swift`
- Create: `ios-app/Scripts/trophy_logic_tests.swift`

**Interfaces:**
- Produces: `enum TrophyCategory: String, Codable, CaseIterable, Identifiable` with cases `totalShots, freeThrowVolume, threePointVolume, midRangeVolume, techniqueVolume, sessionCount, streakDays, bestAccuracy, makeStreak`, computed vars `title: String`, `icon: String`, `thresholds: [Int]` (always 8 entries), `unitSuffix: String`, `exerciseCategoryFilter: String?`. `enum TrophyTier` with `static let names: [String]` (8 entries) and `static let colorHex: [String]` (8 entries). `struct TrophyID: Hashable` with `let category: TrophyCategory`, `let tierIndex: Int`, `var storageKey: String`, `init(category:tierIndex:)`, and a failable `init?(storageKey: String)`.

- [ ] **Step 1: Write the failing test script**

Create `ios-app/Scripts/trophy_logic_tests.swift`:

```swift
import Foundation

// MARK: - Task 1: TrophyCategory & TrophyTier & TrophyID

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
```

- [ ] **Step 2: Run it to verify it fails to compile**

```bash
cd ios-app && swiftc BasketTrainer/Models/Trophies.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests
```
Expected: compile error, `Trophies.swift` doesn't exist yet / `cannot find type 'TrophyCategory' in scope`.

- [ ] **Step 3: Implement `Trophies.swift`**

```swift
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
```

- [ ] **Step 4: Run the test script to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/Trophies.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests && /tmp/trophy_tests
```
Expected: prints `Task 1 assertions passed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/Trophies.swift ios-app/Scripts/trophy_logic_tests.swift
git commit -m "feat: add trophy catalog (categories, tiers, IDs)"
```

---

### Task 2: `ShotSegment` and `WorkoutSession.shotSegments`

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift:267` (insert after the `WorkoutSession` struct's closing brace, before the "Templates de séance complexe" comment block)
- Modify: `ios-app/Scripts/trophy_logic_tests.swift` (append)

**Interfaces:**
- Consumes: `WorkoutSession` (existing, has `series: [ShotSeries]?`, `exerciseType: ExerciseType`, `totalShots: Int`, `results: [Bool]`), `ShotSeries` (existing, has `exerciseType`, `totalShots`, `results`).
- Produces: `struct ShotSegment { let exerciseType: ExerciseType; let totalShots: Int; let results: [Bool] }`, and `WorkoutSession.shotSegments: [ShotSegment]` — used by `TrophyEngine` in Task 4.

- [ ] **Step 1: Append the failing test**

Append to `ios-app/Scripts/trophy_logic_tests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests
```
Expected: `error: value of type 'WorkoutSession' has no member 'shotSegments'`.

- [ ] **Step 3: Implement** — insert into `Models.swift` right after the `WorkoutSession` struct's closing `}` (currently line 267, immediately before the `// ─── Templates de séance complexe ───` comment block):

```swift
// ─────────────────────────────────────────────────
// Segment de tirs uniforme : une séance simple = 1 segment,
// une séance complexe = 1 segment par série. Utilisé par le
// moteur de trophées pour calculer les volumes/streaks sans
// dupliquer la logique simple/complexe déjà éparpillée ailleurs.
// ─────────────────────────────────────────────────
struct ShotSegment {
    let exerciseType: ExerciseType
    let totalShots: Int
    let results: [Bool]
}

extension WorkoutSession {
    var shotSegments: [ShotSegment] {
        if let series = series {
            return series.map {
                ShotSegment(exerciseType: $0.exerciseType, totalShots: $0.totalShots, results: $0.results)
            }
        }
        return [ShotSegment(exerciseType: exerciseType, totalShots: totalShots, results: results)]
    }
}
```

- [ ] **Step 4: Run the test script to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests && /tmp/trophy_tests
```
Expected: prints both `Task 1 assertions passed` and `Task 2 assertions passed`.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift ios-app/Scripts/trophy_logic_tests.swift
git commit -m "feat: add WorkoutSession.shotSegments for uniform simple/complex traversal"
```

---

### Task 3: `TrophyEngine` pure helpers (`longestRun`, `longestConsecutiveDayRun`)

**Files:**
- Create: `ios-app/BasketTrainer/Models/TrophyEngine.swift`
- Modify: `ios-app/Scripts/trophy_logic_tests.swift` (append)

**Interfaces:**
- Produces: `enum TrophyEngine` with `static func longestRun(_ results: [Bool]) -> Int` and `static func longestConsecutiveDayRun(_ days: Set<Date>, cal: Calendar) -> Int`. Both **not** marked `private` (default internal) so Task 4's `evaluate` can use them and so the test script can call them directly.

- [ ] **Step 1: Append the failing test**

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift BasketTrainer/Models/TrophyEngine.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests
```
Expected: `error: cannot find 'TrophyEngine' in scope` (file doesn't exist yet).

- [ ] **Step 3: Implement `TrophyEngine.swift`**

```swift
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
```

- [ ] **Step 4: Run the test script to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift BasketTrainer/Models/TrophyEngine.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests && /tmp/trophy_tests
```
Expected: prints Task 1, 2, and 3 assertions passed.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/TrophyEngine.swift ios-app/Scripts/trophy_logic_tests.swift
git commit -m "feat: add TrophyEngine pure helpers (longestRun, longestConsecutiveDayRun)"
```

---

### Task 4: `TrophyEngine.evaluate` — full history replay

**Files:**
- Modify: `ios-app/BasketTrainer/Models/TrophyEngine.swift` (add to the same `enum TrophyEngine`)
- Modify: `ios-app/Scripts/trophy_logic_tests.swift` (append)

**Interfaces:**
- Consumes: `[WorkoutSession]` (via `.shotSegments` from Task 2), `TrophyCategory.thresholds`/`.exerciseCategoryFilter` (Task 1), `longestRun`/`longestConsecutiveDayRun` (Task 3).
- Produces: `struct TrophyProgress { let unlocks: [TrophyID: Date]; let currentValues: [TrophyCategory: Int] }` and `static func TrophyEngine.evaluate(sessions: [WorkoutSession]) -> TrophyProgress`. This is what `SessionStore` (Task 5) and `TrophiesView` (Task 6) call — no other entry point into the engine is needed.

- [ ] **Step 1: Append the failing test**

```swift
// MARK: - Task 4: TrophyEngine.evaluate

let cal2026 = Calendar(identifier: .gregorian)
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
assert(progress.unlocks[tier0] == date2026(1, 1), "tier0 (100) must be dated to sessionA, the one that actually crossed it")
assert(progress.unlocks[tier1] == date2026(2, 1), "tier1 (250) must be dated to sessionB, not overwritten back to sessionA")
assert(progress.currentValues[.totalShots] == 300)

// (b) Category isolation: an all-freethrow history must not unlock 3pt volume tiers.
let freeThrowOnlyTier0 = TrophyID(category: .freeThrowVolume, tierIndex: 0)
let threePointTier0    = TrophyID(category: .threePointVolume, tierIndex: 0)
assert(progress.unlocks[freeThrowOnlyTier0] != nil)
assert(progress.unlocks[threePointTier0] == nil)
assert(progress.currentValues[.threePointVolume] == 0)

// (c) bestAccuracy ignores segments under 15 shots; makeStreak does not cross segment boundaries.
var complexSession = WorkoutSession(exerciseType: .freethrow, totalShots: 0, madeShots: 0, results: [], date: date2026(3, 1))
complexSession.series = [
    ShotSeries(exerciseType: .freethrow, totalShots: 10, madeShots: 10,
               results: Array(repeating: true, count: 10)),               // 100% but only 10 shots -> ignored for bestAccuracy
    ShotSeries(exerciseType: .threeCenter, totalShots: 20, madeShots: 12,
               results: [true,true,true,true, false, true,true,true,true, false,
                         true,true,true,true, false,false,false,false,false,false])  // 12/20 = 60%, longest run = 4
]
let progress2 = TrophyEngine.evaluate(sessions: [sessionA, sessionB, complexSession])
assert(progress2.currentValues[.bestAccuracy] == 60, "the 10-shot 100% segment must not count (< 15 shots)")
assert(progress2.currentValues[.makeStreak] == 10, "longest run is the 10-shot all-makes segment; must not merge with the second series")

// (d) sessionCount tier crossing at exact threshold.
var fiveSessions: [WorkoutSession] = []
for i in 1...5 {
    fiveSessions.append(WorkoutSession(exerciseType: .freethrow, totalShots: 1, madeShots: 1,
                                        results: [true], date: date2026(4, i)))
}
let progress3 = TrophyEngine.evaluate(sessions: fiveSessions)
assert(progress3.unlocks[TrophyID(category: .sessionCount, tierIndex: 0)] == date2026(4, 5))

print("Task 4 assertions passed")
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift BasketTrainer/Models/TrophyEngine.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests
```
Expected: `error: type 'TrophyEngine' has no member 'evaluate'` (and `TrophyProgress` unresolved).

- [ ] **Step 3: Implement** — append to the `TrophyEngine` enum in `TrophyEngine.swift` (keep the two existing helper functions, add the following alongside them):

```swift
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
```

- [ ] **Step 4: Run the test script to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/SessionStore.swift BasketTrainer/Models/Models.swift BasketTrainer/Models/Trophies.swift BasketTrainer/Models/TrophyEngine.swift Scripts/trophy_logic_tests.swift -o /tmp/trophy_tests && /tmp/trophy_tests
```
Expected: prints Task 1 through Task 4 assertions passed, exit code 0. If any assertion trips, Swift prints the file/line and the assertion message before crashing — fix the implementation (not the test) unless the test itself is wrong.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/TrophyEngine.swift ios-app/Scripts/trophy_logic_tests.swift
git commit -m "feat: implement TrophyEngine.evaluate (full history replay)"
```

---

### Task 5: `SessionStore` integration (persistence, backfill, celebration queue)

**Files:**
- Modify: `ios-app/BasketTrainer/Models/SessionStore.swift`

**Interfaces:**
- Consumes: `TrophyEngine.evaluate(sessions:) -> TrophyProgress` (Task 4), `TrophyID.storageKey` (Task 1).
- Produces: `@Published private(set) var unlockedTrophies: [String: Date]`, `@Published var pendingCelebrations: [TrophyID]`, `func dismissTopCelebration()` — consumed by `TrophiesView` (Task 6) and `CelebrationOverlayView` (Task 7).

This task has no `swiftc`-script test (it depends on `UserDefaults` + `Combine` runtime behavior across app launches, which a one-shot script can't meaningfully exercise) — verify by building for iOS Simulator and a short manual pass using the app's existing "Ajouter une séance manuelle" flow (already wired in `HomeView` → `ManualSessionView`, no new code needed for this).

- [ ] **Step 1: Add the two new `@Published` properties**

In `SessionStore.swift`, right after the existing `@Published private(set) var customSpots: [CustomSpot] = []` (line 15):

```swift
    @Published private(set) var unlockedTrophies: [String: Date] = [:]
    @Published var pendingCelebrations: [TrophyID] = []
```

- [ ] **Step 2: Add the storage key**

Right after `private let customSpotsKey   = "basket_custom_spots"` (line 20):

```swift
    private let trophiesKey = "basket_unlocked_trophies"
```

- [ ] **Step 3: Hook loading + silent backfill into `init()`**

Replace:
```swift
    init() {
        load()
        loadSlots()
        loadSpotPositions()
        loadCustomSpots()
    }
```
with:
```swift
    init() {
        load()
        loadSlots()
        loadSpotPositions()
        loadCustomSpots()
        loadTrophies()
        evaluateTrophies(announceNew: false)
    }
```

- [ ] **Step 4: Add the Trophies section**

Insert after `loadCustomSpots()`'s closing brace (right before the `// ── Persistence ──` comment, i.e. after the existing "// ── Custom Spots ──" section):

```swift
    // ── Trophies ──

    private func evaluateTrophies(announceNew: Bool) {
        let progress = TrophyEngine.evaluate(sessions: sessions)
        var newlyUnlocked: [TrophyID] = []
        for (id, date) in progress.unlocks where unlockedTrophies[id.storageKey] == nil {
            unlockedTrophies[id.storageKey] = date
            newlyUnlocked.append(id)
        }
        guard !newlyUnlocked.isEmpty else { return }
        persistTrophies()
        if announceNew {
            pendingCelebrations.append(contentsOf: newlyUnlocked.sorted { $0.category.rawValue < $1.category.rawValue })
        }
    }

    func dismissTopCelebration() {
        if !pendingCelebrations.isEmpty { pendingCelebrations.removeFirst() }
    }

    private func persistTrophies() {
        if let data = try? JSONEncoder().encode(unlockedTrophies) {
            UserDefaults.standard.set(data, forKey: trophiesKey)
        }
    }

    private func loadTrophies() {
        guard let data = UserDefaults.standard.data(forKey: trophiesKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return }
        unlockedTrophies = decoded
    }
```

- [ ] **Step 5: Call `evaluateTrophies` from `add(_:)` and `update(_:)`**

Replace:
```swift
    func add(_ session: WorkoutSession) {
        sessions.append(session)
        save()
    }

    func update(_ session: WorkoutSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
            save()
        }
    }
```
with:
```swift
    func add(_ session: WorkoutSession) {
        sessions.append(session)
        save()
        evaluateTrophies(announceNew: true)
    }

    func update(_ session: WorkoutSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
            save()
            evaluateTrophies(announceNew: true)
        }
    }
```

- [ ] **Step 6: Build for iOS Simulator to verify it compiles**

```bash
cd ios-app && xcodebuild build -project BasketTrainer.xcodeproj -target BasketTrainer -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. (This project has no shared scheme, hence `-target` rather than `-scheme`.)

- [ ] **Step 7: Manual verification (ask the user to do this on their Mac/Simulator)**

1. Run the app in the Simulator.
2. On the Accueil tab, use "Ajouter une séance manuelle" to log **5 separate sessions**, each: exercise = Lancer Franc, 30 tirs, any make count, today's date (or 5 different recent dates). This pushes `totalShots` to 150 (≥ 100, tier0) and `sessionCount` to 5 (≥ 5, tier0) partway through.
3. Confirm no celebration UI appears yet (Task 6/7 aren't wired to a visible tab or overlay yet — this step is only checking `SessionStore` doesn't crash and persists correctly). Force-quit and relaunch the app.
4. This step has no visible confirmation yet (the UI lands in Tasks 6-8) — its only purpose is to make sure `add()` → `evaluateTrophies()` doesn't crash or hang with real `UserDefaults`. If the app behaves normally (sessions show up in Historique as before), this task is done; full end-to-end verification happens at the end of Task 8.

- [ ] **Step 8: Commit**

```bash
git add ios-app/BasketTrainer/Models/SessionStore.swift
git commit -m "feat: wire trophy evaluation, persistence, and celebration queue into SessionStore"
```

---

### Task 6: `TrophiesView` — the Trophées tab UI

**Files:**
- Create: `ios-app/BasketTrainer/Views/TrophiesView.swift`

**Interfaces:**
- Consumes: `store.sessions`, `store.unlockedTrophies` (Task 5), `TrophyEngine.evaluate(sessions:)` (Task 4), `TrophyCategory.allCases/.title/.icon/.unitSuffix/.thresholds` and `TrophyTier.names/.colorHex` (Task 1).
- Produces: `struct TrophiesView: View` — consumed by `ContentView` (Task 8).

No `swiftc` script test here (references `UIColor`-bridged system colors like `.systemGroupedBackground`/`.tertiarySystemFill`/`.separator`, which only exist in the iOS SDK, not plain macOS Foundation) — verify with an iOS Simulator build (Step 3) plus the end-to-end manual pass at the end of Task 8.

- [ ] **Step 1: Write `TrophiesView.swift`**

```swift
import SwiftUI

struct TrophiesView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        let progress = TrophyEngine.evaluate(sessions: store.sessions)
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(TrophyCategory.allCases) { category in
                            TrophyCategoryCard(
                                category: category,
                                currentValue: progress.currentValues[category] ?? 0,
                                unlockedTrophies: store.unlockedTrophies
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Trophées")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// ─────────────────────────────────────────────────
// Carte d'une piste de trophées : icône + valeur actuelle,
// 8 pastilles de palier, barre de progression vers le prochain.
//
// NOTE: unlock status/dates always come from `unlockedTrophies`
// (SessionStore's persisted record), never from a fresh
// TrophyEngine.evaluate() re-run — a live re-run could show fewer
// unlocks than history once earned (e.g. after deleting a session),
// which would violate the "never revoke" rule. Only the *current
// value* / progress-bar math uses the live recompute.
// ─────────────────────────────────────────────────
struct TrophyCategoryCard: View {
    let category: TrophyCategory
    let currentValue: Int
    let unlockedTrophies: [String: Date]

    private func isUnlocked(_ tier: Int) -> Bool {
        unlockedTrophies[TrophyID(category: category, tierIndex: tier).storageKey] != nil
    }

    private var highestUnlockedTier: Int? {
        (0..<8).reversed().first { isUnlocked($0) }
    }

    private var nextTierIndex: Int? {
        let next = (highestUnlockedTier ?? -1) + 1
        return next < category.thresholds.count ? next : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.icon).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline).foregroundStyle(.primary)
                    Text("\(currentValue)\(category.unitSuffix)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { tier in
                    Circle()
                        .fill(isUnlocked(tier) ? Color(hex: TrophyTier.colorHex[tier]) : Color(.tertiarySystemFill))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(isUnlocked(tier) ? Color.clear : Color(.separator), lineWidth: 1)
                        )
                }
            }

            if let next = nextTierIndex {
                let threshold = category.thresholds[next]
                let previous  = next > 0 ? category.thresholds[next - 1] : 0
                let progress  = threshold > previous
                    ? min(1.0, max(0.0, Double(currentValue - previous) / Double(threshold - previous)))
                    : 0
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("Prochain palier : \(TrophyTier.names[next]) à \(threshold)\(category.unitSuffix)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Tous les paliers obtenus 🏆")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension Color {
    init(hex: String) {
        var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexValue.removeAll { $0 == "#" }
        var rgb: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&rgb)
        self.init(red: Double((rgb & 0xFF0000) >> 16) / 255,
                  green: Double((rgb & 0x00FF00) >> 8) / 255,
                  blue: Double(rgb & 0x0000FF) / 255)
    }
}
```

- [ ] **Step 2: There is no isolated test to run — this view is exercised end-to-end in Task 8's manual pass.** Move on to Step 3 to at least confirm it compiles.

- [ ] **Step 3: Build for iOS Simulator to verify it compiles**

```bash
cd ios-app && xcodebuild build -project BasketTrainer.xcodeproj -target BasketTrainer -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. (`TrophiesView` isn't referenced from `ContentView` yet, so this only proves the file itself is valid Swift/SwiftUI — that's the point of doing it now rather than waiting for Task 8.)

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/TrophiesView.swift
git commit -m "feat: add TrophiesView (Trophées tab UI)"
```

---

### Task 7: `CelebrationOverlayView`

**Files:**
- Create: `ios-app/BasketTrainer/Views/CelebrationOverlayView.swift`

**Interfaces:**
- Consumes: `store.pendingCelebrations: [TrophyID]`, `store.dismissTopCelebration()` (Task 5), `TrophyCategory.icon/.title` and `TrophyTier.names` (Task 1).
- Produces: `struct CelebrationOverlayView: View` — consumed by `ContentView` (Task 8).

- [ ] **Step 1: Write `CelebrationOverlayView.swift`**

```swift
import SwiftUI

struct CelebrationOverlayView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        if let id = store.pendingCelebrations.first {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(id.category.icon).font(.system(size: 56))
                    Text("Trophée débloqué !")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(TrophyTier.names[id.tierIndex]) · \(id.category.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Touchez pour continuer")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 4)
                }
                .padding(28)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .contentShape(Rectangle())
            .onTapGesture { store.dismissTopCelebration() }
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.pendingCelebrations.first)
        }
    }
}
```

- [ ] **Step 2: Build for iOS Simulator to verify it compiles**

```bash
cd ios-app && xcodebuild build -project BasketTrainer.xcodeproj -target BasketTrainer -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. (Not wired into `ContentView` yet — Task 8 does that and is where this actually gets exercised on screen.)

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Views/CelebrationOverlayView.swift
git commit -m "feat: add CelebrationOverlayView"
```

---

### Task 8: Wire into `ContentView` + end-to-end manual verification

**Files:**
- Modify: `ios-app/BasketTrainer/Views/ContentView.swift`

**Interfaces:**
- Consumes: `TrophiesView` (Task 6), `CelebrationOverlayView` (Task 7).

- [ ] **Step 1: Add the tab and the overlay**

Replace the whole file:

```swift
import SwiftUI

// ── Navigation principale : 5 onglets ──
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Accueil",    systemImage: "house.fill")
                }

            HistoryView()
                .tabItem {
                    Label("Historique", systemImage: "clock.fill")
                }

            StatsView()
                .tabItem {
                    Label("Stats",      systemImage: "chart.bar.fill")
                }

            TrophiesView()
                .tabItem {
                    Label("Trophées",   systemImage: "trophy.fill")
                }

            CourtView()
                .tabItem {
                    Label("Terrain",    systemImage: "sportscourt")
                }
        }
        .accentColor(.orange)
        .overlay(CelebrationOverlayView())
    }
}
```

- [ ] **Step 2: Build for iOS Simulator to verify it compiles**

```bash
cd ios-app && xcodebuild build -project BasketTrainer.xcodeproj -target BasketTrainer -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Views/ContentView.swift
git commit -m "feat: add Trophées tab and celebration overlay to ContentView"
```

- [ ] **Step 4: End-to-end manual verification (ask the user to perform this in the Simulator or on their iPhone — this is the real functional proof, everything before it only proved compilation)**

1. Launch the app fresh (delete and reinstall it in the Simulator first, or reset its container, so `UserDefaults` starts empty — otherwise leftover sessions from earlier manual testing in Task 5 will make some trophies unlock silently on first launch, which is correct behavior but makes the "celebration popup" check below ambiguous).
2. Open the **Trophées** tab. Expect: 9 cards, each showing 8 grey/locked pips and "0" as the current value (fresh install, no sessions yet).
3. Go to **Accueil** → "Ajouter une séance manuelle" → log a session: Lancer Franc, 30 tirs, any number made, today. Confirm the app returns to Accueil/Historique normally (no crash).
4. Repeat step 3 four more times (5 manual sessions total, 150 shots). On saving the 5th one, expect the celebration overlay to appear — it will show **one** of the newly-crossed trophies first (multiple triggered at once: `totalShots` tier0 at 100, `freeThrowVolume` tier0 at 100, `sessionCount` tier0 at 5). Tap it to dismiss; confirm the next queued celebration appears; keep tapping until the queue is empty.
5. Open the **Trophées** tab again: confirm "Volume total", "Lancer Franc", and "Séances jouées" each show their Bronze pip filled/colored, with the other two cards' current values matching (150 / 150 / 5), and the other tracks (3 Points, Mi-distance, Technique, Régularité, Meilleure séance, Série de réussites) still fully locked at 0.
6. Force-quit the app and relaunch it. Confirm: no celebration popup appears (the backfill on `init()` is silent), and the Trophées tab still shows the same 3 tiers unlocked as in step 5 (persistence survives relaunch).
7. Note: `bestAccuracy` and `makeStreak` are **not** exercisable this way, because `ManualSessionView` doesn't record a shot-by-shot `results` array (only aggregate made/total counts) — those two tracks are already covered rigorously by Task 4's synthetic-data script tests. This manual pass only needs to confirm the plumbing (`SessionStore` state → UI rendering → persistence → popup) works, which the volume/session-count tracks fully exercise.

If any of the above doesn't match, treat it as a bug in this feature (not a pre-existing issue) and fix it before considering the plan complete.

---

## Self-Review Notes

- **Spec coverage:** all 8 tracks/64 trophies (Task 1), retroactive-with-correct-dates unlocking via full replay (Task 4), never-revoke persistence (Task 5), silent backfill vs. celebration-worthy new unlocks (Task 5), Trophées tab placement between Stats and Terrain (Task 8), celebration popup queued one-at-a-time (Task 7/8), custom spots folding into total-only (implicit — `byCategory` keys only ever match the 4 named categories, "Personnalisé" never matches any `exerciseCategoryFilter`, verified indirectly by Task 4's category-isolation assertion). No spec section is unaddressed.
- **Placeholder scan:** no TBD/TODO; every step has literal code or a literal shell command with expected output.
- **Type consistency:** `TrophyEngine.evaluate(sessions:) -> TrophyProgress` is the single name used everywhere it's called (Task 5's `evaluateTrophies`, Task 6's `TrophiesView.body`) — no drift from an earlier `computeUnlocks` naming used only in the design spec's illustrative sketch. `TrophyID.storageKey` / `TrophyID(storageKey:)` are the only (de)serialization path, used identically in Task 5 (`SessionStore`) and Task 6 (`TrophyCategoryCard.isUnlocked`).
