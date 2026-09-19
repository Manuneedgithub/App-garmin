# Dribble Routines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add timed dribble routines (ordered drill/rest steps) that can be built and played on the iPhone, sent to one of 5 watch slots and played on the Garmin watch, with finished sessions stored in a separate dribble history.

**Architecture:** A self-contained module — pure models (`Dribble.swift`) and a pure timer engine (`DribbleTimerEngine.swift`, tested with a `swiftc` script) — plus a `DribbleStore` (UserDefaults, same pattern as `ProfileStore`) and new SwiftUI views. The watch gets a "Dribble" menu and a wall-clock-driven timer view; routines travel phone→watch as a `"dribbleSlot"` message and sessions come back as a `"dribbleSession"` message routed by a new branch in `GarminManager.receivedMessage`. Nothing in `WorkoutSession`/`SessionStore`/stats/trophies changes.

**Tech Stack:** Swift 5 / SwiftUI (iOS 16 minimum), Combine, UserDefaults + Codable; Monkey C (Connect IQ, Forerunner 255).

**Spec:** `docs/superpowers/specs/2026-09-19-dribble-routines-design.md`

## Global Constraints

- iOS deployment target is **16**: use the single-parameter `.onChange(of:) { newValue in }` form (the two-parameter form is iOS 17+ and fails to compile here). `.alert` with a `TextField` is fine on iOS 16.
- A step is a drill (`drill != nil`, name + seconds) or a rest (`drill == nil`, seconds). Drills are identified by **name (String)**, never by an ID.
- Step seconds: 5…600 in steps of 5 (editor); a routine has at most **20** steps (`DribbleLibrary.maxSteps`).
- Built-in drills, exactly: `Cross`, `Behind the back`, `In and out`, `Between the legs`, `Crossover`, `Hesitation`, `Double cross`, `Pound dribble`. Custom drill names are trimmed, capped at 30 characters, and de-duplicated case-insensitively.
- Watch slots: exactly **5**. A slot holds a **copy** of the routine made at send time.
- Alerts: step changes and the last 3 seconds of a step (countdown only for steps **longer than 3 s**). **No** pause, skip, or start countdown, and no repeat-group ("×3") feature.
- Timing is wall-clock based on both platforms (phone: `Date`; watch: `Time.now()`), never tick counting.
- Storage keys (UserDefaults): `basket_dribble_routines`, `basket_dribble_custom_drills`, `basket_dribble_watch_slots`, `basket_dribble_sessions`. Watch storage keys: `dribbleSlot_0` … `dribbleSlot_4`.
- Message types: phone→watch `"dribbleSlot"` (`index`, `name`, `steps: [{drill: String ("" = rest), seconds: Int}]`); watch→phone `"dribbleSession"` (`routineName`, `startTime` unix, `totalSeconds`, `drillTimes: [{drill, seconds}]`). Shooting-session messages carry **no** `type` key and must keep their current handling.
- Dribble sessions dedupe on exact `(date, routineName)` (the watch may re-send if its completion callback is lost).
- Dribble data never enters Historique/Stats/Trophées/streak calendar.
- This project has **no Xcode test target**. Pure logic (`Dribble.swift`, `DribbleTimerEngine.swift`, no SwiftUI/UIKit) is tested with a `swiftc`-compiled script using `precondition` (never `assert`, which vanishes under `-O`). UI, `DribbleStore` and Monkey C are verified by build and manual pass.
- New Swift files must be registered in `ios-app/BasketTrainer.xcodeproj/project.pbxproj` (Xcode does not pick files up from disk). Each task that adds a file spells out the exact lines. Verify with `plutil -lint` afterwards. **Never** register `Scripts/*.swift` (they contain `@main`).
- Build verification command (run from `ios-app/`; `-scheme`, not `-target`):
  `xcodebuild build -project BasketTrainer.xcodeproj -scheme BasketTrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
- No Monkey C compiler is available in this environment. `.mc` changes are checked by careful inspection (mirror existing code patterns) and must say so in the report/commit message; they need a real build and flash by the user.
- Commits: stage **only** the files a task lists (`git add <files>`), check `git diff --cached --stat`, then commit. The working tree also contains unrelated uncommitted files (`xcuserstate`, `bin/mir/*`, etc.) — never stage them. End every commit message with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` (use a second `-m`).

---

### Task 1: Models, library helpers and formatting (`Dribble.swift`)

**Files:**
- Create: `ios-app/BasketTrainer/Models/Dribble.swift`
- Create: `ios-app/Scripts/dribble_engine_tests.swift`

**Interfaces:**
- Produces (used by every later task):
  - `struct DribbleStep: Codable, Identifiable, Equatable` — `var id = UUID()`, `var drill: String?`, `var seconds: Int`, `var isRest: Bool`. Memberwise init: `DribbleStep(drill: "Cross", seconds: 30)` (drill) / `DribbleStep(seconds: 10)` (rest).
  - `struct DribbleRoutine: Codable, Identifiable, Equatable` — `var id = UUID()`, `var name: String`, `var steps: [DribbleStep]`, `var totalSeconds: Int`. Init: `DribbleRoutine(id:name:steps:)` (`id` defaults).
  - `struct DribbleDrillTime: Codable, Equatable` — `drill: String`, `seconds: Int`.
  - `struct DribbleSession: Codable, Identifiable` — `var id = UUID()`, `routineName: String`, `date: Date`, `totalSeconds: Int`, `drillTimes: [DribbleDrillTime]`, `sentFromWatch: Bool`. Init order: `DribbleSession(routineName:date:totalSeconds:drillTimes:sentFromWatch:)`.
  - `enum DribbleLibrary` — `static let builtInDrills: [String]`, `static let maxSteps = 20`, `static let stepSecondsRange = 5...600`, `static let maxDrillNameLength = 30`, `static func resolveDrill(_ raw: String, known: [String]) -> (name: String, isNew: Bool)?`.
  - `enum DribbleFormat` — `static func duration(_ seconds: Int) -> String` (`"45 s"`, `"1 min"`, `"1 min 30 s"`), `static func clock(_ seconds: Int) -> String` (`"m:ss"`).

- [ ] **Step 1: Write the failing test script**

Create `ios-app/Scripts/dribble_engine_tests.swift`:

```swift
import Foundation

// Minimal assertion helper — precondition (not assert) so it still fires under -O.
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: UInt = #line) {
    precondition(a == b, "line \(line): \(a) != \(b) \(msg)")
}

func drill(_ name: String, _ seconds: Int) -> DribbleStep { DribbleStep(drill: name, seconds: seconds) }
func rest(_ seconds: Int) -> DribbleStep { DribbleStep(seconds: seconds) }

// The routine from the feature request: 30 s cross, 10 s rest, 30 s behind the back, 20 s rest, 1 min between.
let exampleSteps: [DribbleStep] = [
    drill("Cross", 30), rest(10), drill("Behind the back", 30), rest(20), drill("Between the legs", 60),
]

func testModels() {
    expectEqual(rest(10).isRest, true)
    expectEqual(drill("Cross", 30).isRest, false)
    let routine = DribbleRoutine(name: "Ma routine", steps: exampleSteps)
    expectEqual(routine.totalSeconds, 150)
    expectEqual(DribbleRoutine(name: "vide", steps: []).totalSeconds, 0)
    expectEqual(DribbleLibrary.builtInDrills.count, 8)
    expectEqual(DribbleLibrary.builtInDrills.first, "Cross")
    expectEqual(DribbleLibrary.maxSteps, 20)

    // Codable round trip keeps ids and the rest/drill distinction.
    let data = try! JSONEncoder().encode(routine)
    let decoded = try! JSONDecoder().decode(DribbleRoutine.self, from: data)
    expectEqual(decoded, routine)

    let session = DribbleSession(routineName: "Ma routine", date: Date(timeIntervalSince1970: 1_000),
                                 totalSeconds: 150, drillTimes: [DribbleDrillTime(drill: "Cross", seconds: 30)],
                                 sentFromWatch: true)
    let sData = try! JSONEncoder().encode(session)
    let sBack = try! JSONDecoder().decode(DribbleSession.self, from: sData)
    expectEqual(sBack.routineName, "Ma routine")
    expectEqual(sBack.drillTimes, [DribbleDrillTime(drill: "Cross", seconds: 30)])
    expectEqual(sBack.sentFromWatch, true)
}

func testResolveDrill() {
    let known = DribbleLibrary.builtInDrills + ["Wrap around"]
    // empty / whitespace-only → nil
    precondition(DribbleLibrary.resolveDrill("", known: known) == nil)
    precondition(DribbleLibrary.resolveDrill("   \n", known: known) == nil)
    // existing name, different case/spacing → the canonical existing name, not new
    let existing = DribbleLibrary.resolveDrill("  cross ", known: known)
    expectEqual(existing?.name, "Cross")
    expectEqual(existing?.isNew, false)
    let custom = DribbleLibrary.resolveDrill("wrap AROUND", known: known)
    expectEqual(custom?.name, "Wrap around")
    expectEqual(custom?.isNew, false)
    // genuinely new name → trimmed, flagged new
    let fresh = DribbleLibrary.resolveDrill("  Spider dribble ", known: known)
    expectEqual(fresh?.name, "Spider dribble")
    expectEqual(fresh?.isNew, true)
    // capped at 30 characters
    let long = DribbleLibrary.resolveDrill(String(repeating: "x", count: 50), known: known)
    expectEqual(long?.name.count, 30)
    expectEqual(long?.isNew, true)
}

func testFormat() {
    expectEqual(DribbleFormat.duration(45), "45 s")
    expectEqual(DribbleFormat.duration(60), "1 min")
    expectEqual(DribbleFormat.duration(90), "1 min 30 s")
    expectEqual(DribbleFormat.duration(150), "2 min 30 s")
    expectEqual(DribbleFormat.clock(0), "0:00")
    expectEqual(DribbleFormat.clock(5), "0:05")
    expectEqual(DribbleFormat.clock(65), "1:05")
    expectEqual(DribbleFormat.clock(-3), "0:00")
}

@main
struct DribbleTests {
    static func main() {
        testModels()
        testResolveDrill()
        testFormat()
        print("Task 1 assertions passed")
    }
}
```

- [ ] **Step 2: Run it to verify it fails to compile**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: error — `Dribble.swift` does not exist / `cannot find type 'DribbleStep' in scope`.

- [ ] **Step 3: Implement `Dribble.swift`**

```swift
import Foundation

// ─────────────────────────────────────────────────
// ROUTINES DE DRIBBLE — modèles purs (aucune dépendance UI)
// ─────────────────────────────────────────────────

struct DribbleStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var drill: String?        // nil = repos
    var seconds: Int

    var isRest: Bool { drill == nil }
}

struct DribbleRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var steps: [DribbleStep]

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
}

struct DribbleDrillTime: Codable, Equatable {
    var drill: String
    var seconds: Int
}

struct DribbleSession: Codable, Identifiable {
    var id = UUID()
    var routineName: String
    var date: Date                    // heure de départ ; (date, routineName) dédoublonne les renvois montre
    var totalSeconds: Int
    var drillTimes: [DribbleDrillTime]
    var sentFromWatch: Bool
}

enum DribbleLibrary {
    static let builtInDrills = [
        "Cross", "Behind the back", "In and out", "Between the legs",
        "Crossover", "Hesitation", "Double cross", "Pound dribble",
    ]
    static let maxSteps = 20
    static let stepSecondsRange = 5...600
    static let maxDrillNameLength = 30

    // Résout un nom saisi par l'utilisateur : nil si vide, le nom canonique existant
    // (comparaison insensible à la casse) s'il est déjà connu, sinon le nom nettoyé
    // marqué `isNew`.
    static func resolveDrill(_ raw: String, known: [String]) -> (name: String, isNew: Bool)? {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxDrillNameLength))
        guard !trimmed.isEmpty else { return nil }
        if let match = known.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return (match, false)
        }
        return (trimmed, true)
    }
}

enum DribbleFormat {
    // "45 s", "1 min", "1 min 30 s"
    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    // "m:ss"
    static func clock(_ seconds: Int) -> String {
        let t = max(seconds, 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
```

- [ ] **Step 4: Run the test script to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests" && "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: prints `Task 1 assertions passed`, exit code 0, no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/Dribble.swift ios-app/Scripts/dribble_engine_tests.swift
git diff --cached --stat
git commit -m "feat: add dribble routine models, drill resolution and formatting" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Timer engine — current state

**Files:**
- Create: `ios-app/BasketTrainer/Models/DribbleTimerEngine.swift`
- Modify: `ios-app/Scripts/dribble_engine_tests.swift`

**Interfaces:**
- Consumes: `DribbleStep` (Task 1).
- Produces:
  - `struct DribbleTimerState: Equatable { var stepIndex: Int; var secondsLeftInStep: Int; var isFinished: Bool }` — when finished, `stepIndex == steps.count` and `secondsLeftInStep == 0`.
  - `enum DribbleAlert: Equatable { case stepChanged(newIndex: Int); case countdown(secondsLeft: Int); case finished }` (declared here, produced by Task 3).
  - `enum DribbleTimerEngine` with `static func state(for steps: [DribbleStep], elapsed: Int) -> DribbleTimerState`.

- [ ] **Step 1: Write the failing test**

In `ios-app/Scripts/dribble_engine_tests.swift`, add this function above `@main` and add the call `testState()` and its print inside `main()` (after `testFormat()`), changing the final print to `print("Task 1-2 assertions passed")`:

```swift
func testState() {
    // Example routine: Cross 0–30, rest 30–40, BTB 40–70, rest 70–90, Between 90–150.
    func s(_ e: Int) -> DribbleTimerState { DribbleTimerEngine.state(for: exampleSteps, elapsed: e) }
    expectEqual(s(0),   DribbleTimerState(stepIndex: 0, secondsLeftInStep: 30, isFinished: false))
    expectEqual(s(29),  DribbleTimerState(stepIndex: 0, secondsLeftInStep: 1,  isFinished: false))
    expectEqual(s(30),  DribbleTimerState(stepIndex: 1, secondsLeftInStep: 10, isFinished: false))
    expectEqual(s(39),  DribbleTimerState(stepIndex: 1, secondsLeftInStep: 1,  isFinished: false))
    expectEqual(s(40),  DribbleTimerState(stepIndex: 2, secondsLeftInStep: 30, isFinished: false))
    expectEqual(s(70),  DribbleTimerState(stepIndex: 3, secondsLeftInStep: 20, isFinished: false))
    expectEqual(s(90),  DribbleTimerState(stepIndex: 4, secondsLeftInStep: 60, isFinished: false))
    expectEqual(s(149), DribbleTimerState(stepIndex: 4, secondsLeftInStep: 1,  isFinished: false))
    // finished exactly at the total, and stays finished
    expectEqual(s(150), DribbleTimerState(stepIndex: 5, secondsLeftInStep: 0, isFinished: true))
    expectEqual(s(9999), DribbleTimerState(stepIndex: 5, secondsLeftInStep: 0, isFinished: true))
    // negative elapsed behaves like 0
    expectEqual(s(-5), s(0))
    // empty routine is immediately finished
    expectEqual(DribbleTimerEngine.state(for: [], elapsed: 0),
                DribbleTimerState(stepIndex: 0, secondsLeftInStep: 0, isFinished: true))
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift BasketTrainer/Models/DribbleTimerEngine.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: error — `DribbleTimerEngine.swift` doesn't exist / `cannot find 'DribbleTimerEngine' in scope`.

- [ ] **Step 3: Implement `DribbleTimerEngine.swift`**

```swift
import Foundation

// ─────────────────────────────────────────────────
// MOTEUR DE MINUTEUR DRIBBLE — pur, sans UI ni Timer.
// Prend les secondes écoulées depuis le départ (horloge murale) et
// répond : quelle étape, combien de secondes restantes, quelles alertes.
// ─────────────────────────────────────────────────

struct DribbleTimerState: Equatable {
    var stepIndex: Int            // == steps.count quand terminé
    var secondsLeftInStep: Int
    var isFinished: Bool
}

enum DribbleAlert: Equatable {
    case stepChanged(newIndex: Int)
    case countdown(secondsLeft: Int)   // 3, 2, 1
    case finished
}

enum DribbleTimerEngine {
    static func state(for steps: [DribbleStep], elapsed: Int) -> DribbleTimerState {
        let t = max(elapsed, 0)
        var end = 0
        for (i, step) in steps.enumerated() {
            end += step.seconds
            if t < end {
                return DribbleTimerState(stepIndex: i, secondsLeftInStep: end - t, isFinished: false)
            }
        }
        return DribbleTimerState(stepIndex: steps.count, secondsLeftInStep: 0, isFinished: true)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift BasketTrainer/Models/DribbleTimerEngine.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests" && "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: prints `Task 1-2 assertions passed`, exit 0, no warnings.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/DribbleTimerEngine.swift ios-app/Scripts/dribble_engine_tests.swift
git diff --cached --stat
git commit -m "feat: add dribble timer engine (current step and seconds left)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Timer engine — alerts and per-drill times

**Files:**
- Modify: `ios-app/BasketTrainer/Models/DribbleTimerEngine.swift`
- Modify: `ios-app/Scripts/dribble_engine_tests.swift`

**Interfaces:**
- Consumes: `DribbleStep`, `DribbleDrillTime` (Task 1); `DribbleAlert`, `DribbleTimerEngine` (Task 2).
- Produces (inside `enum DribbleTimerEngine`):
  - `static func alerts(for steps: [DribbleStep], from: Int, to: Int) -> [DribbleAlert]` — every alert for whole seconds `t` with `from < t <= to`, in ascending order. A step of `seconds > 3` emits `.countdown(3)`, `.countdown(2)`, `.countdown(1)` at `end-3`, `end-2`, `end-1`; at `t == end` of a step it emits `.stepChanged(newIndex: i+1)`, or `.finished` for the last step. `from < 0` is treated as 0; `to <= from` or empty steps → `[]`. `.finished` is emitted exactly once across any partition of `0…total`.
  - `static func drillTimes(for steps: [DribbleStep]) -> [DribbleDrillTime]` — total seconds per drill name (rests excluded), in order of first appearance.

- [ ] **Step 1: Write the failing tests**

In `dribble_engine_tests.swift` add these functions above `@main`, add `testAlerts()` and `testDrillTimes()` calls to `main()`, and change the final print to `print("Task 1-3 assertions passed")`:

```swift
func testAlerts() {
    func a(_ from: Int, _ to: Int, _ steps: [DribbleStep] = exampleSteps) -> [DribbleAlert] {
        DribbleTimerEngine.alerts(for: steps, from: from, to: to)
    }
    // First step: countdown 3-2-1 then the change to step 1, all within 0→30.
    expectEqual(a(0, 30), [.countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
                           .stepChanged(newIndex: 1)])
    // One second at a time: nothing until 27, then exactly one alert per second.
    expectEqual(a(0, 26), [])
    expectEqual(a(26, 27), [.countdown(secondsLeft: 3)])
    expectEqual(a(29, 30), [.stepChanged(newIndex: 1)])
    expectEqual(a(30, 31), [])
    // Big jump (app was backgrounded): every crossed boundary reported once, ascending.
    expectEqual(a(25, 41), [
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .stepChanged(newIndex: 1),
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .stepChanged(newIndex: 2),
    ])
    // Whole routine: 5 steps × (3 countdowns + 1 boundary) = 20 alerts, 4 stepChanged, ends with finished.
    let all = a(0, 150)
    expectEqual(all.count, 20)
    expectEqual(all.filter { if case .stepChanged = $0 { return true } else { return false } }.count, 4)
    expectEqual(all.last, .finished)
    // finished exactly once, whatever the partition, and never after the end
    expectEqual(a(0, 500).filter { $0 == .finished }.count, 1)
    expectEqual(a(150, 200), [])
    expectEqual(a(0, 75).count + a(75, 150).count, 20)
    // Short steps (≤ 3 s) never emit a countdown.
    let short = [drill("A", 3), drill("B", 5)]
    expectEqual(a(0, 8, short), [
        .stepChanged(newIndex: 1),
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .finished,
    ])
    // Degenerate ranges
    expectEqual(a(10, 10), [])
    expectEqual(a(20, 10), [])
    expectEqual(a(0, 5, []), [])
    expectEqual(a(-5, 30).count, a(0, 30).count)
}

func testDrillTimes() {
    // Rests excluded; repeated drill summed; order of first appearance.
    let steps = [drill("Cross", 30), rest(10), drill("Cross", 20), drill("Behind the back", 15), rest(5)]
    expectEqual(DribbleTimerEngine.drillTimes(for: steps), [
        DribbleDrillTime(drill: "Cross", seconds: 50),
        DribbleDrillTime(drill: "Behind the back", seconds: 15),
    ])
    expectEqual(DribbleTimerEngine.drillTimes(for: exampleSteps), [
        DribbleDrillTime(drill: "Cross", seconds: 30),
        DribbleDrillTime(drill: "Behind the back", seconds: 30),
        DribbleDrillTime(drill: "Between the legs", seconds: 60),
    ])
    expectEqual(DribbleTimerEngine.drillTimes(for: [rest(10)]), [])
    expectEqual(DribbleTimerEngine.drillTimes(for: []), [])
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift BasketTrainer/Models/DribbleTimerEngine.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: error — `type 'DribbleTimerEngine' has no member 'alerts'` (and `drillTimes`).

- [ ] **Step 3: Implement**

Inside `enum DribbleTimerEngine` in `DribbleTimerEngine.swift`, after `state(for:elapsed:)`, add:

```swift
    // Alertes pour chaque seconde entière t avec from < t <= to, dans l'ordre croissant.
    // Robuste aux sauts (app en arrière-plan) : chaque frontière franchie est signalée une fois.
    static func alerts(for steps: [DribbleStep], from: Int, to: Int) -> [DribbleAlert] {
        let lo = max(from, 0)
        guard to > lo, !steps.isEmpty else { return [] }
        var result: [DribbleAlert] = []
        var end = 0
        for (i, step) in steps.enumerated() {
            end += step.seconds
            if step.seconds > 3 {
                for k in stride(from: 3, through: 1, by: -1) {
                    let t = end - k
                    if t > lo && t <= to { result.append(.countdown(secondsLeft: k)) }
                }
            }
            if end > lo && end <= to {
                result.append(i == steps.count - 1 ? .finished : .stepChanged(newIndex: i + 1))
            }
        }
        return result
    }

    // Secondes cumulées par exercice (repos exclus), dans l'ordre de première apparition.
    static func drillTimes(for steps: [DribbleStep]) -> [DribbleDrillTime] {
        var order: [String] = []
        var totals: [String: Int] = [:]
        for step in steps {
            guard let drill = step.drill else { continue }
            if totals[drill] == nil { order.append(drill) }
            totals[drill, default: 0] += step.seconds
        }
        return order.map { DribbleDrillTime(drill: $0, seconds: totals[$0] ?? 0) }
    }
```

(Ordering is already ascending: within a step the countdowns are at `end-3 < end-2 < end-1 < end`, and the next step's earliest event is after `end`. No sort is needed.)

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios-app && swiftc BasketTrainer/Models/Dribble.swift BasketTrainer/Models/DribbleTimerEngine.swift Scripts/dribble_engine_tests.swift -o "${TMPDIR:-/tmp}/dribble_tests" && "${TMPDIR:-/tmp}/dribble_tests"
```
Expected: prints `Task 1-3 assertions passed`, exit 0, no warnings. If an assertion trips, fix the implementation (not the test) unless you can show the test's expected value is wrong.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/DribbleTimerEngine.swift ios-app/Scripts/dribble_engine_tests.swift
git diff --cached --stat
git commit -m "feat: dribble timer engine alerts and per-drill times" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `DribbleStore`, Xcode registration, app injection

**Files:**
- Create: `ios-app/BasketTrainer/Models/DribbleStore.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`
- Modify: `ios-app/BasketTrainer/BasketTrainerApp.swift`

**Interfaces:**
- Consumes: `DribbleRoutine`, `DribbleSession`, `DribbleLibrary.builtInDrills`, `DribbleLibrary.resolveDrill` (Task 1).
- Produces — `final class DribbleStore: ObservableObject`:
  - `static let shared`, `static let watchSlotCount = 5`
  - `@Published private(set) var routines: [DribbleRoutine]`, `customDrills: [String]`, `watchSlots: [DribbleRoutine?]` (always 5 entries), `sessions: [DribbleSession]`
  - `var allDrills: [String]` (built-ins + customs)
  - `func save(_ routine: DribbleRoutine)` (insert or replace by id), `func delete(_ routine: DribbleRoutine)`
  - `func resolveDrill(_ raw: String) -> String?` — canonical name; registers a new custom drill when needed
  - `func setWatchSlot(_ index: Int, routine: DribbleRoutine?)` (ignores out-of-range)
  - `@discardableResult func add(_ session: DribbleSession) -> Bool` — `false` (not added) on exact `(date, routineName)` duplicate
  - `func deleteSession(_ session: DribbleSession)`
- Environment: `BasketTrainerApp` injects a `DribbleStore` as an environment object (later views use `@EnvironmentObject var dribbleStore: DribbleStore`).

This task has no `swiftc` test (it depends on `UserDefaults`); verification is the build.

- [ ] **Step 1: Create `DribbleStore.swift`**

```swift
import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE DRIBBLE — routines, exercices perso, emplacements montre, historique.
// Même conventions que ProfileStore/SessionStore (UserDefaults + Codable).
// ─────────────────────────────────────────────────
final class DribbleStore: ObservableObject {
    static let shared = DribbleStore()
    static let watchSlotCount = 5

    @Published private(set) var routines: [DribbleRoutine] = []
    @Published private(set) var customDrills: [String] = []
    @Published private(set) var watchSlots: [DribbleRoutine?] = Array(repeating: nil, count: DribbleStore.watchSlotCount)
    @Published private(set) var sessions: [DribbleSession] = []

    private let routinesKey     = "basket_dribble_routines"
    private let customDrillsKey = "basket_dribble_custom_drills"
    private let watchSlotsKey   = "basket_dribble_watch_slots"
    private let sessionsKey     = "basket_dribble_sessions"

    init() {
        if let v: [DribbleRoutine] = load(routinesKey) { routines = v }
        if let v: [String] = load(customDrillsKey) { customDrills = v }
        if let v: [DribbleRoutine?] = load(watchSlotsKey), v.count == Self.watchSlotCount { watchSlots = v }
        if let v: [DribbleSession] = load(sessionsKey) { sessions = v }
    }

    var allDrills: [String] { DribbleLibrary.builtInDrills + customDrills }

    // ── Routines ──

    func save(_ routine: DribbleRoutine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[i] = routine
        } else {
            routines.append(routine)
        }
        persist(routines, routinesKey)
    }

    func delete(_ routine: DribbleRoutine) {
        routines.removeAll { $0.id == routine.id }
        persist(routines, routinesKey)
    }

    // ── Exercices ──

    // Nom canonique d'un exercice saisi (nil si vide). Enregistre un nouvel exercice perso au besoin.
    func resolveDrill(_ raw: String) -> String? {
        guard let resolved = DribbleLibrary.resolveDrill(raw, known: allDrills) else { return nil }
        if resolved.isNew {
            customDrills.append(resolved.name)
            persist(customDrills, customDrillsKey)
        }
        return resolved.name
    }

    // ── Emplacements montre (copie de la routine au moment de l'envoi) ──

    func setWatchSlot(_ index: Int, routine: DribbleRoutine?) {
        guard watchSlots.indices.contains(index) else { return }
        watchSlots[index] = routine
        persist(watchSlots, watchSlotsKey)
    }

    // ── Historique ──

    @discardableResult
    func add(_ session: DribbleSession) -> Bool {
        // La montre peut renvoyer une séance déjà livrée (callback de fin perdu) — on l'ignore.
        if sessions.contains(where: { $0.date == session.date && $0.routineName == session.routineName }) {
            return false
        }
        sessions.append(session)
        persist(sessions, sessionsKey)
        return true
    }

    func deleteSession(_ session: DribbleSession) {
        sessions.removeAll { $0.id == session.id }
        persist(sessions, sessionsKey)
    }

    // ── Persistence ──

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
```

- [ ] **Step 2: Register the three model files in `project.pbxproj`**

Files to register (all live in the `Models` group): `Dribble.swift`, `DribbleTimerEngine.swift`, `DribbleStore.swift`. UUIDs (verified unused; `AD0` is the current highest): 

| File | PBXFileReference UUID | PBXBuildFile UUID |
|---|---|---|
| Dribble.swift | `AA0000000000000000000AD1` | `AA0000000000000000000AD2` |
| DribbleTimerEngine.swift | `AA0000000000000000000AD3` | `AA0000000000000000000AD4` |
| DribbleStore.swift | `AA0000000000000000000AD5` | `AA0000000000000000000AD6` |

Before editing, run `grep -c "AA0000000000000000000AD[1-6]" ios-app/BasketTrainer.xcodeproj/project.pbxproj` and confirm `0`. Then make four insertions (tab-indented like neighbours):

1. In the `PBXBuildFile` section, after the line containing `LiveRoutineView.swift in Sources */ = {isa = PBXBuildFile;`, add:
```
		AA0000000000000000000AD2 /* Dribble.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AD1 /* Dribble.swift */; };
		AA0000000000000000000AD4 /* DribbleTimerEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AD3 /* DribbleTimerEngine.swift */; };
		AA0000000000000000000AD6 /* DribbleStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AD5 /* DribbleStore.swift */; };
```
2. In the `PBXFileReference` section, after the line containing `/* LiveRoutineView.swift */ = {isa = PBXFileReference;`, add:
```
		AA0000000000000000000AD1 /* Dribble.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Dribble.swift; sourceTree = "<group>"; };
		AA0000000000000000000AD3 /* DribbleTimerEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleTimerEngine.swift; sourceTree = "<group>"; };
		AA0000000000000000000AD5 /* DribbleStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleStore.swift; sourceTree = "<group>"; };
```
3. In the **Models** `PBXGroup` children list (the one that contains `/* ProfileStore.swift */,` and `/* TrophyEngine.swift */,`), after the line `AA00000000000000000000F6 /* TrophyEngine.swift */,` add:
```
				AA0000000000000000000AD1 /* Dribble.swift */,
				AA0000000000000000000AD3 /* DribbleTimerEngine.swift */,
				AA0000000000000000000AD5 /* DribbleStore.swift */,
```
4. In the target's `PBXSourcesBuildPhase` `files` list, after the line `AA0000000000000000000AD0 /* LiveRoutineView.swift in Sources */,` add:
```
				AA0000000000000000000AD2 /* Dribble.swift in Sources */,
				AA0000000000000000000AD4 /* DribbleTimerEngine.swift in Sources */,
				AA0000000000000000000AD6 /* DribbleStore.swift in Sources */,
```

Verify: `plutil -lint ios-app/BasketTrainer.xcodeproj/project.pbxproj` prints `OK`; each fileRef UUID (`AD1`,`AD3`,`AD5`) appears exactly 3 times and each build-file UUID (`AD2`,`AD4`,`AD6`) exactly 2 times.

- [ ] **Step 3: Inject the store in `BasketTrainerApp.swift`**

Add the state object after `@StateObject private var profileStore = ProfileStore.shared`:
```swift
    @StateObject private var dribbleStore = DribbleStore.shared
```
and add, after `.environmentObject(profileStore)`:
```swift
                .environmentObject(dribbleStore)
```

- [ ] **Step 4: Build to verify**

Run the build verification command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/DribbleStore.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj ios-app/BasketTrainer/BasketTrainerApp.swift
git diff --cached --stat
git commit -m "feat: add DribbleStore and register dribble model files" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Routine editor view

**Files:**
- Create: `ios-app/BasketTrainer/Views/DribbleRoutineEditorView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DribbleStore` (`save`, `allDrills`, `resolveDrill`) via `@EnvironmentObject var dribbleStore: DribbleStore`; `DribbleStep`, `DribbleRoutine`, `DribbleLibrary.maxSteps`/`stepSecondsRange`, `DribbleFormat.duration` (Task 1).
- Produces: `struct DribbleRoutineEditorView: View` with `init(routine: DribbleRoutine?)` — `nil` creates a new routine (new `UUID`), non-nil edits it (same `id`). On save it calls `dribbleStore.save(...)` and dismisses. Presented as a sheet by Task 8.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR DE ROUTINE DRIBBLE — nom + liste ordonnée d'étapes
// (exercice + durée, ou repos + durée).
// ─────────────────────────────────────────────────
struct DribbleRoutineEditorView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss

    private let routineID: UUID
    @State private var name: String
    @State private var steps: [DribbleStep]
    @State private var showDrillPicker = false

    init(routine: DribbleRoutine?) {
        routineID = routine?.id ?? UUID()
        _name  = State(initialValue: routine?.name ?? "")
        _steps = State(initialValue: routine?.steps ?? [])
    }

    private var canAddStep: Bool { steps.count < DribbleLibrary.maxSteps }
    private var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. Routine handle 5 min", text: $name)
                }

                Section {
                    ForEach($steps) { $step in
                        DribbleStepRow(step: $step)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showDrillPicker = true
                    } label: {
                        Label("Ajouter un exercice", systemImage: "plus.circle")
                            .foregroundStyle(.orange)
                    }
                    .disabled(!canAddStep)

                    Button {
                        steps.append(DribbleStep(seconds: 10))
                    } label: {
                        Label("Ajouter un repos", systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    }
                    .disabled(!canAddStep)
                } header: {
                    Text("Étapes (\(steps.count)/\(DribbleLibrary.maxSteps))")
                } footer: {
                    if !steps.isEmpty {
                        Text("Durée totale : \(DribbleFormat.duration(totalSeconds))")
                    }
                }
            }
            .navigationTitle(routineTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                    EditButton().foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showDrillPicker) {
                DribbleDrillPickerSheet { drillName in
                    steps.append(DribbleStep(drill: drillName, seconds: 30))
                }
            }
        }
    }

    private var routineTitle: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nouvelle routine" : name
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        dribbleStore.save(DribbleRoutine(id: routineID, name: trimmed, steps: steps))
        dismiss()
    }
}

private struct DribbleStepRow: View {
    @Binding var step: DribbleStep

    var body: some View {
        HStack {
            if let drill = step.drill {
                Image(systemName: "figure.basketball").foregroundStyle(.orange)
                Text(drill).lineLimit(1)
            } else {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
                Text("Repos").foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(DribbleFormat.duration(step.seconds),
                    value: $step.seconds,
                    in: DribbleLibrary.stepSecondsRange,
                    step: 5)
                .fixedSize()
        }
    }
}

// Liste des exercices (fournis + perso) avec création d'un nouvel exercice.
private struct DribbleDrillPickerSheet: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss
    let onPick: (String) -> Void

    @State private var showNewDrill = false
    @State private var newDrillName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(dribbleStore.allDrills, id: \.self) { drill in
                        Button {
                            onPick(drill)
                            dismiss()
                        } label: {
                            Text(drill).foregroundStyle(.primary)
                        }
                    }
                }
                Section {
                    Button {
                        newDrillName = ""
                        showNewDrill = true
                    } label: {
                        Label("Nouvel exercice…", systemImage: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
            .alert("Nouvel exercice", isPresented: $showNewDrill) {
                TextField("Nom (ex. Spider dribble)", text: $newDrillName)
                Button("Annuler", role: .cancel) {}
                Button("Ajouter") {
                    if let name = dribbleStore.resolveDrill(newDrillName) {
                        onPick(name)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 2: Register `DribbleRoutineEditorView.swift` in `project.pbxproj`**

UUIDs (verify unused with `grep -c "AA0000000000000000000AD[78]"` → `0`): fileRef `AA0000000000000000000AD7`, buildFile `AA0000000000000000000AD8`. Four insertions:

1. `PBXBuildFile` — after the line containing `DribbleStore.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000AD8 /* DribbleRoutineEditorView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AD7 /* DribbleRoutineEditorView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* DribbleStore.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000AD7 /* DribbleRoutineEditorView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleRoutineEditorView.swift; sourceTree = "<group>"; };
```
3. **Views** `PBXGroup` children (the group containing `/* LiveRoutineView.swift */,`) — after that line:
```
				AA0000000000000000000AD7 /* DribbleRoutineEditorView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000AD6 /* DribbleStore.swift in Sources */,`:
```
				AA0000000000000000000AD8 /* DribbleRoutineEditorView.swift in Sources */,
```
Verify with `plutil -lint` → `OK`; `AD7` appears exactly 3×, `AD8` exactly 2×.

- [ ] **Step 3: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`, no new warnings from `DribbleRoutineEditorView.swift`.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/DribbleRoutineEditorView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add dribble routine editor" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Timer view (phone)

**Files:**
- Create: `ios-app/BasketTrainer/Views/DribbleTimerView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DribbleTimerEngine.state/alerts/drillTimes`, `DribbleAlert`, `DribbleTimerState` (Tasks 2–3); `DribbleRoutine`, `DribbleSession`, `DribbleFormat.clock` (Task 1); `DribbleStore.add` (Task 4) via `@EnvironmentObject`.
- Produces: `struct DribbleTimerView: View` with `init(routine: DribbleRoutine)`. Plays the routine live (0.25 s tick on wall-clock `Date`), fires haptic + system sound on alerts, keeps the screen awake, shows a summary at the end with "Enregistrer" (adds a `DribbleSession` with `sentFromWatch: false`) and "Quitter". Presented full-screen by Task 8.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import AudioToolbox
import UIKit

// ─────────────────────────────────────────────────
// MINUTEUR DRIBBLE (iPhone) — joue une routine étape par étape.
// Temps calculé sur l'horloge murale (Date) : pas de dérive si l'app
// est ralentie ou passe en arrière-plan.
// ─────────────────────────────────────────────────
struct DribbleTimerView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss

    let routine: DribbleRoutine

    @State private var startDate = Date()
    @State private var elapsed = 0
    @State private var finished = false
    @State private var showQuitConfirm = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var state: DribbleTimerState {
        DribbleTimerEngine.state(for: routine.steps, elapsed: elapsed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if finished { summaryContent } else { runContent }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        if finished || elapsed == 0 { dismiss() } else { showQuitConfirm = true }
                    }
                    .foregroundStyle(.orange)
                }
            }
            .alert("Quitter la routine ?", isPresented: $showQuitConfirm) {
                Button("Continuer", role: .cancel) {}
                Button("Quitter", role: .destructive) { dismiss() }
            } message: {
                Text("La séance en cours ne sera pas enregistrée.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { _ in tick() }
    }

    // ── Déroulement ──

    private func tick() {
        guard !finished else { return }
        let now = Int(Date().timeIntervalSince(startDate))
        guard now != elapsed else { return }
        let alerts = DribbleTimerEngine.alerts(for: routine.steps, from: elapsed, to: now)
        // Après un long saut (arrière-plan) on ne joue que la dernière alerte, pas une rafale.
        if let last = alerts.last { fire(last) }
        elapsed = now
        if DribbleTimerEngine.state(for: routine.steps, elapsed: now).isFinished {
            finished = true
        }
    }

    private func fire(_ alert: DribbleAlert) {
        switch alert {
        case .stepChanged, .finished:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
        case .countdown:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1104)
        }
    }

    // ── Écran en cours ──

    private var runContent: some View {
        let st = state
        let steps = routine.steps
        let current: DribbleStep? = st.stepIndex < steps.count ? steps[st.stepIndex] : nil
        let next: DribbleStep? = st.stepIndex + 1 < steps.count ? steps[st.stepIndex + 1] : nil
        let total = max(routine.totalSeconds, 1)

        return VStack(spacing: 28) {
            ProgressView(value: Double(min(elapsed, total)), total: Double(total))
                .tint(.orange)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Text("Étape \(min(st.stepIndex + 1, steps.count)) / \(steps.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 10) {
                Text(current?.drill ?? "Repos")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(current?.isRest == true ? Color.blue : Color.orange)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Text(DribbleFormat.clock(st.secondsLeftInStep))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 10) {
                Text("Ensuite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(next.map { $0.drill ?? "Repos" } ?? "Fin de la routine")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let next {
                    Text(DribbleFormat.duration(next.seconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // ── Résumé ──

    private var summaryContent: some View {
        let times = DribbleTimerEngine.drillTimes(for: routine.steps)
        return ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("🎉").font(.system(size: 44))
                    Text("Routine terminée")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text(DribbleFormat.duration(routine.totalSeconds))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    ForEach(times, id: \.drill) { t in
                        HStack {
                            Text(t.drill)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(DribbleFormat.duration(t.seconds))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    save()
                } label: {
                    Text("Enregistrer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func save() {
        dribbleStore.add(DribbleSession(
            routineName: routine.name,
            date: startDate,
            totalSeconds: routine.totalSeconds,
            drillTimes: DribbleTimerEngine.drillTimes(for: routine.steps),
            sentFromWatch: false
        ))
        dismiss()
    }
}
```

- [ ] **Step 2: Register `DribbleTimerView.swift` in `project.pbxproj`**

UUIDs (verify unused: `grep -c "AA0000000000000000000AD[9A]"` → `0`): fileRef `AA0000000000000000000AD9`, buildFile `AA0000000000000000000ADA`. Same four insertions as Task 5, chained after the editor's lines:

1. `PBXBuildFile` — after the line containing `DribbleRoutineEditorView.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000ADA /* DribbleTimerView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AD9 /* DribbleTimerView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* DribbleRoutineEditorView.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000AD9 /* DribbleTimerView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleTimerView.swift; sourceTree = "<group>"; };
```
3. **Views** group children — after `AA0000000000000000000AD7 /* DribbleRoutineEditorView.swift */,`:
```
				AA0000000000000000000AD9 /* DribbleTimerView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000AD8 /* DribbleRoutineEditorView.swift in Sources */,`:
```
				AA0000000000000000000ADA /* DribbleTimerView.swift in Sources */,
```
Verify `plutil -lint` → `OK`; `AD9` 3×, `ADA` 2×.

- [ ] **Step 3: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/DribbleTimerView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add dribble timer view with step alerts" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Phone side of the watch link (`GarminManager`)

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

**Interfaces:**
- Consumes: `DribbleRoutine`, `DribbleSession`, `DribbleDrillTime` (Task 1); `DribbleStore.shared.add` (Task 4).
- Produces:
  - `@Published var lastDribbleSlotSendMessage: String?` (same role as `lastCustomSpotsSendMessage`)
  - `func sendDribbleSlot(_ index: Int, routine: DribbleRoutine)` — same wake-then-send pattern as `sendCustomSpots`, message `{"type": "dribbleSlot", "index": Int, "name": String, "steps": [{"drill": String ("" = rest), "seconds": Int}]}`
  - `receivedMessage` routes `{"type": "dribbleSession", ...}` to `DribbleStore` (`sentFromWatch: true`); dictionaries without that type go to `parseAndStore` exactly as before.

- [ ] **Step 1: Add the published message property**

After `@Published var lastCustomSpotsSendMessage: String? = nil` add:
```swift
    @Published var lastDribbleSlotSendMessage: String? = nil
```

- [ ] **Step 2: Route incoming messages by type**

Replace the body of `receivedMessage`:
```swift
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        parseAndStore(dict)
    }
```
with:
```swift
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        // Les séances de tirs n'ont pas de clé "type" — elles gardent leur chemin habituel.
        if (dict["type"] as? String) == "dribbleSession" {
            parseDribbleSession(dict)
            return
        }
        parseAndStore(dict)
    }

    private func parseDribbleSession(_ dict: [String: Any]) {
        let routineName = dict["routineName"] as? String ?? "Routine"
        let startTime   = dict["startTime"]   as? Int ?? 0
        let totalSecs   = dict["totalSeconds"] as? Int ?? 0
        let rawTimes    = dict["drillTimes"]  as? [[String: Any]] ?? []
        let drillTimes  = rawTimes.compactMap { entry -> DribbleDrillTime? in
            guard let drill = entry["drill"] as? String,
                  let secs  = entry["seconds"] as? Int else { return nil }
            return DribbleDrillTime(drill: drill, seconds: secs)
        }
        let session = DribbleSession(
            routineName: routineName,
            date: Date(timeIntervalSince1970: TimeInterval(startTime)),
            totalSeconds: totalSecs,
            drillTimes: drillTimes,
            sentFromWatch: true
        )
        DispatchQueue.main.async {
            DribbleStore.shared.add(session)   // ignore un renvoi identique de la montre
        }
    }
```

- [ ] **Step 3: Add `sendDribbleSlot`**

Insert before `func addMockSession() {`:
```swift
    func sendDribbleSlot(_ index: Int, routine: DribbleRoutine) {
        guard let device = connectedDevice else {
            lastDribbleSlotSendMessage = "Montre non connectée"
            return
        }
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        let steps: [[String: Any]] = routine.steps.map {
            ["drill": $0.drill ?? "", "seconds": $0.seconds]
        }
        let payload: [String: Any] = [
            "type": "dribbleSlot",
            "index": index,
            "name": routine.name,
            "steps": steps
        ]
        sdk.openAppRequest(app) { [weak self] _ in
            self?.sdk.sendMessage(payload, to: app, progress: nil) { result in
                print("sendDribbleSlot(\(index)) → \(NSStringFromSendMessageResult(result))")
                DispatchQueue.main.async {
                    self?.lastDribbleSlotSendMessage = result == .success
                        ? "Routine envoyée à la montre ✅"
                        : "Échec de l'envoi : \(NSStringFromSendMessageResult(result))"
                }
            }
        }
    }
```

- [ ] **Step 4: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`. Manually confirm by reading the diff that (a) `parseAndStore` is byte-for-byte unchanged and (b) dictionaries without a `type` key still reach it.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git diff --cached --stat
git commit -m "feat: send dribble routines to the watch and receive dribble sessions" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Dribble home, history views and Home entry point

**Files:**
- Create: `ios-app/BasketTrainer/Views/DribbleHomeView.swift`
- Create: `ios-app/BasketTrainer/Views/DribbleHistoryView.swift`
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DribbleStore` (`routines`, `watchSlots`, `sessions`, `delete`, `setWatchSlot`, `deleteSession`), `GarminManager.sendDribbleSlot` / `lastDribbleSlotSendMessage` (Task 7), `DribbleRoutineEditorView(routine:)` (Task 5), `DribbleTimerView(routine:)` (Task 6), `DribbleFormat` (Task 1). Both stores/managers come from `@EnvironmentObject`.
- Produces: `struct DribbleHomeView: View` (sheet root, own `NavigationStack`), `struct DribbleHistoryView: View`, and a "Dribble" button on `HomeView`.

- [ ] **Step 1: Create `DribbleHomeView.swift`**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// DRIBBLE — bibliothèque de routines : lancer, modifier, envoyer à la montre.
// ─────────────────────────────────────────────────
private struct DribbleEditorTarget: Identifiable {
    let id = UUID()
    let routine: DribbleRoutine?      // nil = nouvelle routine
}

struct DribbleHomeView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editorTarget: DribbleEditorTarget? = nil
    @State private var runningRoutine: DribbleRoutine? = nil

    var body: some View {
        NavigationStack {
            Group {
                if dribbleStore.routines.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(dribbleStore.routines) { routine in
                            routineRow(routine)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dribble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DribbleHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button {
                        editorTarget = DribbleEditorTarget(routine: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                DribbleRoutineEditorView(routine: target.routine)
            }
            .fullScreenCover(item: $runningRoutine) { routine in
                DribbleTimerView(routine: routine)
            }
            .alert("Envoi à la montre", isPresented: Binding(
                get: { garmin.lastDribbleSlotSendMessage != nil },
                set: { if !$0 { garmin.lastDribbleSlotSendMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garmin.lastDribbleSlotSendMessage ?? "")
            }
        }
    }

    private func routineRow(_ routine: DribbleRoutine) -> some View {
        HStack(spacing: 12) {
            Button {
                runningRoutine = routine
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(routine.steps.count) étapes · \(DribbleFormat.duration(routine.totalSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)

            Menu {
                Button("Modifier") { editorTarget = DribbleEditorTarget(routine: routine) }
                Menu("Envoyer à la montre") {
                    ForEach(0..<DribbleStore.watchSlotCount, id: \.self) { i in
                        Button("Emplacement \(i + 1) — \(dribbleStore.watchSlots[i]?.name ?? "vide")") {
                            dribbleStore.setWatchSlot(i, routine: routine)
                            garmin.sendDribbleSlot(i, routine: routine)
                        }
                    }
                }
                Button("Supprimer", role: .destructive) { dribbleStore.delete(routine) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏀").font(.system(size: 52))
            Text("Aucune routine")
                .font(.title3.bold())
            Text("Enchaîne des exercices de dribble et des repos, par exemple 30 s cross, 10 s repos, 30 s behind the back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                editorTarget = DribbleEditorTarget(routine: nil)
            } label: {
                Label("Créer une routine", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
    }
}
```

- [ ] **Step 2: Create `DribbleHistoryView.swift`**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// HISTORIQUE DRIBBLE — séances terminées (téléphone ou montre).
// Séparé de l'historique de tirs : pas de tirs, pas de pourcentage.
// ─────────────────────────────────────────────────
struct DribbleHistoryView: View {
    @EnvironmentObject var dribbleStore: DribbleStore

    private var sorted: [DribbleSession] {
        dribbleStore.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                VStack(spacing: 10) {
                    Text("Aucune séance de dribble")
                        .font(.headline)
                    Text("Les routines terminées apparaissent ici.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(sorted) { session in
                        NavigationLink {
                            DribbleSessionDetailView(session: session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.routineName).font(.headline)
                                        if session.sentFromWatch { Text("⌚").font(.caption2) }
                                    }
                                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(DribbleFormat.duration(session.totalSeconds))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { dribbleStore.deleteSession(sorted[i]) }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Historique dribble")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DribbleSessionDetailView: View {
    let session: DribbleSession

    var body: some View {
        List {
            Section {
                row("Date", session.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                row("Durée totale", DribbleFormat.duration(session.totalSeconds))
                row("Source", session.sentFromWatch ? "Montre" : "iPhone")
            }
            Section("Temps par exercice") {
                if session.drillTimes.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }
                ForEach(session.drillTimes, id: \.drill) { t in
                    row(t.drill, DribbleFormat.duration(t.seconds))
                }
            }
        }
        .navigationTitle(session.routineName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Add the entry point in `HomeView.swift`**

Three edits:

(a) In `private enum HomeSheet`, add the case and its id — change
```swift
    case routine
    case slotsConfig
```
to
```swift
    case routine
    case dribble
    case slotsConfig
```
and, in `var id`, after `case .routine:         return "routine"` add:
```swift
        case .dribble:         return "dribble"
```
(b) In the `.sheet(item: $activeSheet)` switch, after
```swift
                case .routine:
                    LiveRoutineView()
```
add:
```swift
                case .dribble:
                    DribbleHomeView()
```
(c) Show the button under the existing routine button: change
```swift
                        routineButton
                            .padding(.horizontal, 20)
```
to
```swift
                        routineButton
                            .padding(.horizontal, 20)

                        dribbleButton
                            .padding(.horizontal, 20)
```
and add this property just before `private var recentSessionsList: some View {`:
```swift
    private var dribbleButton: some View {
        Button {
            activeSheet = .dribble
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dribble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Routines chronométrées, sur le tél. ou la montre")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
```

- [ ] **Step 4: Register both new views in `project.pbxproj`**

UUIDs (verify unused: `grep -c "AA0000000000000000000AD[B-E]"` → `0`): 

| File | fileRef | buildFile |
|---|---|---|
| DribbleHistoryView.swift | `AA0000000000000000000ADB` | `AA0000000000000000000ADC` |
| DribbleHomeView.swift | `AA0000000000000000000ADD` | `AA0000000000000000000ADE` |

Insertions (same four places as before, chained after the Timer view lines):
1. `PBXBuildFile` — after the line containing `DribbleTimerView.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000ADC /* DribbleHistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000ADB /* DribbleHistoryView.swift */; };
		AA0000000000000000000ADE /* DribbleHomeView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000ADD /* DribbleHomeView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* DribbleTimerView.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000ADB /* DribbleHistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleHistoryView.swift; sourceTree = "<group>"; };
		AA0000000000000000000ADD /* DribbleHomeView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DribbleHomeView.swift; sourceTree = "<group>"; };
```
3. **Views** group children — after `AA0000000000000000000AD9 /* DribbleTimerView.swift */,`:
```
				AA0000000000000000000ADB /* DribbleHistoryView.swift */,
				AA0000000000000000000ADD /* DribbleHomeView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000ADA /* DribbleTimerView.swift in Sources */,`:
```
				AA0000000000000000000ADC /* DribbleHistoryView.swift in Sources */,
				AA0000000000000000000ADE /* DribbleHomeView.swift in Sources */,
```
Verify `plutil -lint` → `OK`; `ADB`,`ADD` 3× each; `ADC`,`ADE` 2× each.

- [ ] **Step 5: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Views/DribbleHomeView.swift ios-app/BasketTrainer/Views/DribbleHistoryView.swift ios-app/BasketTrainer/Views/HomeView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add dribble home, history and Home entry point" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Watch — store incoming dribble slots (`BasketApp.mc`)

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`

**Interfaces:**
- Consumes: the phone message `{"type": "dribbleSlot", "index", "name", "steps": [{"drill", "seconds"}]}` (Task 7).
- Produces: `Application.Storage` key `"dribbleSlot_<0-4>"` holding `{"name" => String, "steps" => Array of {"drill" => String ("" = rest), "seconds" => Number}}`, or `null` (cleared) when the message contains no valid step. Task 10 reads this exact shape.

No Monkey C compiler is available here — write it by mirroring the existing `customSpots` branch style, then re-read it once for balanced braces/parentheses.

- [ ] **Step 1: Add the `dribbleSlot` branch**

In `onPhoneAppMessage`, immediately **before** the line
```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("customSpots")) {
```
insert:
```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("dribbleSlot")) {
            var dSlot = dict["index"];
            // Nested/Top-level integers from the phone can arrive as Long — accept both.
            if (!(dSlot instanceof Number || dSlot instanceof Long) || dSlot < 0 || dSlot > 4) { return; }
            if (!(dict["name"] instanceof String) || !(dict["steps"] instanceof Array)) { return; }
            var dRaw   = dict["steps"] as Array;
            var dClean = [];
            for (var d = 0; d < dRaw.size(); d++) {
                var dEntry = dRaw[d];
                if (!(dEntry instanceof Dictionary)) { continue; }
                var dSecs = dEntry["seconds"];
                if (!(dSecs instanceof Number || dSecs instanceof Long) || dSecs < 1) { continue; }
                var dDrill = dEntry["drill"];
                if (!(dDrill instanceof String)) { dDrill = ""; }
                dClean.add({ "drill" => dDrill, "seconds" => dSecs.toNumber() });
            }
            if (dClean.size() == 0) {
                Application.Storage.setValue("dribbleSlot_" + dSlot.toString(), null);
            } else {
                Application.Storage.setValue("dribbleSlot_" + dSlot.toString(),
                    { "name" => dict["name"], "steps" => dClean });
            }
        }
```

- [ ] **Step 2: Inspect**

Re-read the whole edited `onPhoneAppMessage` and confirm: the new block is a complete `if { ... }`; no variable name collides with a variable declared in the same scope (all new names start with `d`); the existing `slot` and `customSpots` branches are untouched. Run a crude brace balance check and expect equal counts:
```bash
python3 - <<'PY'
s = open("garmin-app/source/BasketApp.mc", encoding="utf-8").read()
print("braces", s.count("{"), s.count("}"), "parens", s.count("("), s.count(")"))
PY
```

- [ ] **Step 3: Commit**

```bash
git add garmin-app/source/BasketApp.mc
git diff --cached --stat
git commit -m "feat(watch): store dribble slots received from the phone" -m "Not compile-verified: no Monkey C compiler in this environment, checked by inspection against the existing customSpots branch." -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Watch — Dribble menu, timer view, completion message

**Files:**
- Create: `garmin-app/source/DribbleMenu.mc`
- Create: `garmin-app/source/DribbleView.mc`
- Modify: `garmin-app/source/MainMenu.mc`

**Interfaces:**
- Consumes: `Application.Storage` keys `dribbleSlot_<i>` (Task 9). Existing `TransmitListener(dict)` class (defined in `SummaryView.mc`; enqueues into `PendingQueue` on send error).
- Produces: a fourth main-menu entry "Dribble" (id 3) → `DribbleSlotMenuView` (5 slots) → `DribbleRunView`. On completion transmits `{"type": "dribbleSession", "routineName": String, "startTime": Number (unix), "totalSeconds": Number, "drillTimes": [{"drill": String, "seconds": Number}]}` (the shape `GarminManager.parseDribbleSession` reads — Task 7). Global helper functions `dribbleClock(Number) -> String`, `dribbleTotalSeconds(Array) -> Number`, `dribbleVibe(Number)`; classes `DribbleSlotMenuView`, `DribbleSlotMenuDelegate`, `DribbleRun`, `DribbleRunView`, `DribbleRunDelegate`.

No Monkey C compiler is available: mirror the existing files' idioms exactly (`import` lists, `as Number` casts, `Menu2` usage as in `ExerciseMenu.mc`/`SlotMenu.mc`, drawing style as in `RoutineSeriesDoneView`). Rules to reproduce the phone engine: step `end` = cumulative seconds; a step with `seconds > 3` vibrates lightly at `end-3`, `end-2`, `end-1`; strongly at `end` (step change or finish).

- [ ] **Step 1: Create `DribbleMenu.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

// ─────────────────────────────────────────────────
// MENU DRIBBLE — 5 emplacements de routines reçues du téléphone
// ─────────────────────────────────────────────────

// m:ss
function dribbleClock(totalSeconds as Number) as String {
    var m = totalSeconds / 60;
    var s = totalSeconds % 60;
    return m.toString() + ":" + s.format("%02d");
}

function dribbleTotalSeconds(steps as Array) as Number {
    var t = 0;
    for (var i = 0; i < steps.size(); i++) {
        t += (steps[i] as Dictionary)["seconds"] as Number;
    }
    return t;
}

class DribbleSlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Dribble"});
        for (var i = 0; i < 5; i++) {
            var def   = Application.Storage.getValue("dribbleSlot_" + i.toString());
            var label = "Routine " + (i + 1).toString();
            var sub   = "vide";
            if (def instanceof Dictionary && def["name"] instanceof String && def["steps"] instanceof Array) {
                label = def["name"] as String;
                sub   = dribbleClock(dribbleTotalSeconds(def["steps"] as Array));
            }
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class DribbleSlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId() as Number;
        var def   = Application.Storage.getValue("dribbleSlot_" + index.toString());
        if (!(def instanceof Dictionary) || !(def["steps"] instanceof Array)) { return; }
        var run  = new DribbleRun(def as Dictionary);
        var view = new DribbleRunView(run);
        var del  = new DribbleRunDelegate(run);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

- [ ] **Step 2: Create `DribbleView.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.Attention;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// ROUTINE DRIBBLE SUR LA MONTRE — minuteur sur l'horloge murale
// (Time.now), vibrations aux changements d'étape et sur les 3
// dernières secondes. Envoie la séance au téléphone à la fin.
// ─────────────────────────────────────────────────

function dribbleVibe(durationMs as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(100, durationMs)]);
    }
}

class DribbleRun {
    var name      as String;
    var steps     as Array;    // [{"drill" => String ("" = rest), "seconds" => Number}]
    var startTime as Number;   // unix
    var lastT     as Number;   // last second already processed for alerts
    var total     as Number;
    var finished  as Boolean;

    function initialize(def as Dictionary) {
        name      = def["name"] as String;
        steps     = def["steps"] as Array;
        startTime = Time.now().value();
        lastT     = 0;
        total     = dribbleTotalSeconds(steps);
        finished  = false;
    }

    function elapsed() as Number {
        var e = Time.now().value() - startTime;
        return (e < 0) ? 0 : e;
    }

    function secondsAt(i as Number) as Number {
        return (steps[i] as Dictionary)["seconds"] as Number;
    }

    function drillAt(i as Number) as String {
        return (steps[i] as Dictionary)["drill"] as String;
    }

    // Index of the step running at second t; steps.size() once finished.
    function stepIndexAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t < end) { return i; }
        }
        return steps.size();
    }

    function secondsLeftAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t < end) { return end - t; }
        }
        return 0;
    }

    // Same rules as DribbleTimerEngine.alerts on the phone:
    // 2 = step change / finish (t == end of a step), 1 = last-3-seconds tick
    // (only for steps longer than 3 s), 0 = nothing.
    function alertAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t == end) { return 2; }
            if (secondsAt(i) > 3 && t >= end - 3 && t < end) { return 1; }
        }
        return 0;
    }

    // Vibrates once (strongest alert crossed since the last call), returns true once finished.
    function advance() as Boolean {
        var e = elapsed();
        var strongest = 0;
        for (var t = lastT + 1; t <= e && t <= total; t++) {
            var a = alertAt(t);
            if (a > strongest) { strongest = a; }
        }
        lastT = (e > total) ? total : e;
        if (strongest == 2) {
            dribbleVibe(400);
        } else if (strongest == 1) {
            dribbleVibe(120);
        }
        if (e >= total) { finished = true; }
        return finished;
    }

    // Seconds per drill (rests excluded), in order of first appearance.
    function drillTimes() as Array {
        var out = [];
        for (var i = 0; i < steps.size(); i++) {
            var drill = drillAt(i);
            if (drill.equals("")) { continue; }
            var found = false;
            for (var j = 0; j < out.size(); j++) {
                var d = out[j] as Dictionary;
                if ((d["drill"] as String).equals(drill)) {
                    d["seconds"] = (d["seconds"] as Number) + secondsAt(i);
                    found = true;
                    break;
                }
            }
            if (!found) {
                out.add({ "drill" => drill, "seconds" => secondsAt(i) });
            }
        }
        return out;
    }

    function toDictionary() as Dictionary {
        return {
            "type"         => "dribbleSession",
            "routineName"  => name,
            "startTime"    => startTime,
            "totalSeconds" => total,
            "drillTimes"   => drillTimes()
        };
    }
}

class DribbleRunView extends WatchUi.View {
    private var _run   as DribbleRun;
    private var _timer as Timer.Timer or Null;
    private var _sent  as Boolean;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_BLUE   = 0x3399FF;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;

    function initialize(run as DribbleRun) {
        View.initialize();
        _run   = run;
        _timer = null;
        _sent  = false;
    }

    function onShow() as Void {
        if (_timer == null && !_run.finished) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
    }

    function onHide() as Void {
        stopTimer();
    }

    function onTick() as Void {
        if (_run.advance()) {
            stopTimer();
            sendResult();
        }
        WatchUi.requestUpdate();
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    private function sendResult() as Void {
        if (_sent) { return; }
        _sent = true;
        var dict = _run.toDictionary();
        // TransmitListener (SummaryView.mc) queues the dict in PendingQueue if the send fails.
        Communications.transmit(dict, null, new TransmitListener(dict));
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_run.finished) {
            dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 60, Graphics.FONT_SMALL, "Routine terminée",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 100, Graphics.FONT_TINY, _run.name,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, 140, Graphics.FONT_NUMBER_MEDIUM, dribbleClock(_run.total),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 208, Graphics.FONT_XTINY, "▶ Terminer",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var t   = _run.elapsed();
        var idx = _run.stepIndexAt(t);
        var n   = _run.steps.size();
        if (idx >= n) { idx = n - 1; }   // between the last second and the finishing tick

        var drill  = _run.drillAt(idx);
        var isRest = drill.equals("");
        var label  = isRest ? "Repos" : drill;

        // Header: routine name + step counter
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 28, Graphics.FONT_XTINY,
                    _run.name + "  " + (idx + 1).toString() + "/" + n.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Current step
        dc.setColor(isRest ? COLOR_BLUE : COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 64, Graphics.FONT_SMALL, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Seconds left in the step
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 122, Graphics.FONT_NUMBER_MEDIUM, dribbleClock(_run.secondsLeftAt(t)),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Next step
        var nextText = "Fin";
        if (idx + 1 < n) {
            var nd = _run.drillAt(idx + 1);
            nextText = nd.equals("") ? "Repos" : nd;
        }
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 188, Graphics.FONT_XTINY, "Ensuite : " + nextText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "↩ Abandonner",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class DribbleRunDelegate extends WatchUi.BehaviorDelegate {
    private var _run as DribbleRun;

    function initialize(run as DribbleRun) {
        BehaviorDelegate.initialize();
        _run = run;
    }

    // Finished: SELECT closes the summary. (Mid-routine SELECT does nothing — no pause/skip.)
    function onSelect() as Boolean {
        if (_run.finished) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        return true;
    }

    // BACK abandons a running routine (nothing is sent) or closes the summary.
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
```

- [ ] **Step 3: Add the "Dribble" entry to `MainMenu.mc`**

In `MainMenuView.initialize`, after
```monkeyc
        addItem(new WatchUi.MenuItem("Entraînements",     null, 2, null));
```
add:
```monkeyc
        addItem(new WatchUi.MenuItem("Dribble",           null, 3, null));
```
In `MainMenuDelegate.onSelect`, replace the final branch
```monkeyc
        } else if (id == 2) {
            var menu = new SlotMenuView();
            var del  = new SlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
```
with
```monkeyc
        } else if (id == 2) {
            var menu = new SlotMenuView();
            var del  = new SlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else if (id == 3) {
            var menu = new DribbleSlotMenuView();
            var del  = new DribbleSlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
```

- [ ] **Step 4: Inspect (no compiler)**

Re-read all three files. Confirm: every function/class has balanced braces; each `import` you rely on is listed (`Toybox.Attention`, `Toybox.Timer`, `Toybox.Time`, `Toybox.Communications`); `TransmitListener` and `dribbleTotalSeconds`/`dribbleClock` are referenced by their exact names; `DribbleRunDelegate` is constructed with one argument in `DribbleMenu.mc`; the phone-side message keys in `toDictionary()` exactly match Task 7 (`routineName`, `startTime`, `totalSeconds`, `drillTimes`, each with `drill`/`seconds`). Run the crude balance check on each file and expect equal counts:
```bash
python3 - <<'PY'
for f in ["DribbleMenu.mc", "DribbleView.mc", "MainMenu.mc"]:
    s = open("garmin-app/source/" + f, encoding="utf-8").read()
    print(f, "braces", s.count("{"), s.count("}"), "parens", s.count("("), s.count(")"))
PY
```

- [ ] **Step 5: Commit**

```bash
git add garmin-app/source/DribbleMenu.mc garmin-app/source/DribbleView.mc garmin-app/source/MainMenu.mc
git diff --cached --stat
git commit -m "feat(watch): dribble menu, wall-clock timer view and session upload" -m "Not compile-verified: no Monkey C compiler in this environment, checked by inspection against existing menu/view code. Needs a real build and flash." -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Final manual verification (by the user, after all tasks)

1. Rebuild and copy the watch `.prg` (Monkey C: Build for Device → `garmin-app/bin/garminapp.prg` → `GARMIN/APPS/`). If the build fails, send the compiler errors.
2. iPhone: Accueil → **Dribble** → create the example routine (Cross 30 s, Repos 10 s, Behind the back 30 s, Repos 20 s, Between the legs 60 s); add a custom drill; reorder/delete steps.
3. iPhone: play it — check the step names, the countdown, the beeps/haptics at step changes and the last 3 seconds, the summary, **Enregistrer**, then it appears in the dribble history and **not** in Historique/Stats.
4. iPhone: **Envoyer à la montre** → an emplacement; the alert says the send succeeded.
5. Watch: main menu → **Dribble** → the routine is listed with its total time → run it; check vibrations; at the end the session shows up in the iPhone dribble history with the ⌚ badge, and only once even if you restart the watch app.

---

## Self-Review Notes

- **Spec coverage:** models/limits/library (Task 1); wall-clock engine — state, alerts incl. countdown-only->3 s and once-only finish, drill times (Tasks 2–3); the four stores incl. 5-slot copies and `(date, routineName)` dedupe (Task 4); editor with add-drill/custom drill/rest/reorder/delete and 20-step cap (Task 5); phone timer with haptic + sound, idle-timer disabled, quit confirm, summary/save (Task 6); `dribbleSlot` send, `dribbleSession` routing that leaves shooting messages untouched (Task 7); Home entry, routine list/edit/send-to-slot, separate history (Task 8); watch storage with Number-or-Long handling (Task 9); watch menu, timer, vibrations, completion transmit via the existing `PendingQueue` retry path (Task 10); manual checklist for what cannot be automated. Out-of-scope items (pause, skip, start countdown, repeat groups, stats/trophy integration, watch-side editing) have no task, on purpose.
- **Placeholder scan:** none; every step has literal code or a literal command. pbxproj UUIDs `AD1`–`ADE` are pre-allocated and checked unused (`AD0` was the highest).
- **Type consistency:** `DribbleTimerEngine.state/alerts/drillTimes`, `DribbleAlert`, `DribbleTimerState`, `DribbleStore` members, `DribbleRoutineEditorView(routine:)`, `DribbleTimerView(routine:)`, `sendDribbleSlot(_:routine:)`, and the watch message keys are named identically in every task that touches them.
