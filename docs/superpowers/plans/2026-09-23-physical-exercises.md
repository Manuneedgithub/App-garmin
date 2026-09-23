# Physical Exercises Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Physique" training type — single physical exercises (Chrono or Durée fixe) run one at a time with multiple attempts per session — that can be built and played on the iPhone, sent to one of 5 watch slots and played on the Garmin watch, with finished sessions stored in a separate physical-exercises history.

**Architecture:** A self-contained module mirroring the existing Dribble module — pure models (`Physical.swift`) and a tiny pure timing helper (`PhysicalTimer.swift`, tested with a `swiftc` script) — plus a `PhysicalStore` (UserDefaults, same pattern as `DribbleStore`) and new SwiftUI views. The watch gets a fifth "Physique" menu item and a run view driven by the existing button idioms (`onNextPage`/`onPreviousPage`/`onSelect`); sessions travel phone→watch as a `"physicalSlot"` message and come back as a `"physicalSession"` message, both routed by one more branch in the places Dribble already added branches to (`GarminManager.receivedMessage`, `BasketApp.onPhoneAppMessage`). Nothing in `WorkoutSession`/`SessionStore`/`DribbleStore`/stats/trophies changes.

**Tech Stack:** Swift 5 / SwiftUI (iOS 16 minimum), Combine, UserDefaults + Codable; Monkey C (Connect IQ, Forerunner 255).

**Spec:** `docs/superpowers/specs/2026-09-23-physical-exercises-design.md`

## Global Constraints

- iOS deployment target is **16**: use the single-parameter `.onChange(of:) { newValue in }` form if you need one (this plan doesn't need any); no iOS 17-only API.
- An exercise has a fixed `kind` set at creation: **`.chrono`** (stopwatch — `fixedSeconds` is `nil`) or **`.duration`** (fixed-duration countdown — `fixedSeconds` is always a non-nil `Int` in `5...600`, step 5). This invariant is enforced by the editor (Task 3) and never violated elsewhere; later tasks may assume it.
- A session holds **multiple attempts**: `PhysicalAttempt` carries either `seconds: Double?` (chrono) or `reps: Int?` (duration) — never both non-nil for one attempt, and the unused field is `nil`.
- Exercise and custom-drill-style name cap: `PhysicalLibrary.maxNameLength = 30`. Rep cap per attempt: `PhysicalLibrary.maxRepsPerAttempt = 50`.
- Built-in exercises, exactly: `25m` (chrono), `50m` (chrono), `100m` (chrono), `Suicide` (chrono), `1 min aller-retour sprint` (duration, 60s) — see the exact array in Task 1.
- Watch slots: exactly **5**. A slot holds a **copy** of the exercise made at send time (same rule as Dribble).
- No step/routine structure (unlike Dribble): one exercise, run repeatedly as separate attempts, until the user ends the session.
- Timing is wall-clock based on both platforms (phone: `Date`; watch: `Time.now()`), never tick counting. Remaining seconds in a countdown are **ceiling-rounded** (`55.9s` elapsed in a `60s` countdown shows `5`, not `4`) — identically on both platforms.
- Storage keys (UserDefaults): `basket_physical_exercises`, `basket_physical_watch_slots`, `basket_physical_sessions`. Watch storage keys: `physicalSlot_0` … `physicalSlot_4`.
- Message types: phone→watch `"physicalSlot"` (`index`, `name`, `kind` ("chrono"/"duration"), `seconds` — present and ≥5 only when `kind == "duration"`, absent for `"chrono"`); watch→phone `"physicalSession"` (`exerciseName`, `kind`, `startTime` unix, `attempts: [{seconds: Double} | {reps: Int}]`). Shooting-session messages carry **no** `type` key and Dribble messages carry `"dribbleSlot"`/`"dribbleSession"` — none of this plan's work changes their handling.
- Physical sessions dedupe on exact `(date, exerciseName)`, exactly like Dribble sessions dedupe on `(date, routineName)`.
- Physical data never enters Historique/Stats/Trophées/streak calendar.
- This project has **no Xcode test target**. Pure logic (`Physical.swift`, `PhysicalTimer.swift`, no SwiftUI/UIKit) is tested with a `swiftc`-compiled script using `precondition` (never `assert`, which vanishes under `-O`). UI, `PhysicalStore` and Monkey C are verified by build and manual pass.
- New Swift files must be registered in `ios-app/BasketTrainer.xcodeproj/project.pbxproj` (Xcode does not pick files up from disk). Each task that adds a file spells out the exact lines — already verified to apply cleanly and compile (see each task). Verify with `plutil -lint` afterwards. **Never** register `Scripts/*.swift` (they contain `@main`).
- Build verification command (run from `ios-app/`; `-scheme`, not `-target`):
  `xcodebuild build -project BasketTrainer.xcodeproj -scheme BasketTrainer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
- A Connect IQ SDK **and compiler are available in this environment** (not the case for earlier work on this project — don't assume otherwise): `monkeyc` lives at `"$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc"`, with `garmin-app/developer_key` and the `fr255` device already set up. Compile verification command (run from `garmin-app/`, **always** write `-o` to a scratchpad path, never into `bin/`, which is tracked):
  `"$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" -d fr255 -f monkey.jungle -o "${TMPDIR:-/tmp}/physical-check.prg" -y developer_key -w`
  Expect `BUILD SUCCESSFUL` with only the one pre-existing warning (`_sync` unused in `BasketApp.mc`). This compiles but does not run the code — no device or simulator run happens here, so watch tasks still end with "not run on a real device" in their commit message even though they ARE compile-verified.
- Commits: stage **only** the files a task lists (`git add <files>`), check `git diff --cached --stat`, then commit. The working tree also contains unrelated uncommitted files (`xcuserstate`, `bin/mir/*`, etc.) — never stage them. End every commit message with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` (use a second `-m`).

---

### Task 1: Models, library helpers and formatting (`Physical.swift` + `PhysicalTimer.swift`)

**Files:**
- Create: `ios-app/BasketTrainer/Models/Physical.swift`
- Create: `ios-app/BasketTrainer/Models/PhysicalTimer.swift`
- Create: `ios-app/Scripts/physical_tests.swift`

**Interfaces:**
- Produces (used by every later task):
  - `enum PhysicalExerciseKind: String, Codable { case chrono, duration }`
  - `struct PhysicalExercise: Codable, Identifiable, Equatable` — `var id = UUID()`, `var name: String`, `var kind: PhysicalExerciseKind`, `var fixedSeconds: Int?`. No custom init — the synthesized memberwise init gives `fixedSeconds` an implicit `nil` default, so `PhysicalExercise(name: "25m", kind: .chrono)` compiles (confirmed, mirrors `DribbleStep`'s `drill: String?`).
  - `struct PhysicalAttempt: Codable, Equatable` — `var seconds: Double?`, `var reps: Int?`.
  - `struct PhysicalSession: Codable, Identifiable` — `var id = UUID()`, `var exerciseName: String`, `var kind: PhysicalExerciseKind`, `var date: Date`, `var attempts: [PhysicalAttempt]`, `var sentFromWatch: Bool`.
  - `enum PhysicalLibrary` — `static let builtIn: [PhysicalExercise]`, `static let maxNameLength = 30`, `static let fixedSecondsRange = 5...600`, `static let maxRepsPerAttempt = 50`.
  - `enum PhysicalFormat` — `static func chronoResult(_ seconds: Double) -> String`, `static func repsResult(_ reps: Int) -> String`, `static func duration(_ seconds: Int) -> String`, `static func runningClock(_ seconds: Double) -> String`.
  - `enum PhysicalTimer` — `static func secondsRemaining(fixedSeconds: Int, elapsed: Double) -> Int`, `static func isFinished(fixedSeconds: Int, elapsed: Double) -> Bool`.

- [ ] **Step 1: Write the failing test script**

Create `ios-app/Scripts/physical_tests.swift`:

```swift
import Foundation

// Minimal assertion helper — precondition (not assert) so it still fires under -O.
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: UInt = #line) {
    precondition(a == b, "line \(line): \(a) != \(b) \(msg)")
}

func testModels() {
    expectEqual(PhysicalLibrary.builtIn.count, 5)
    expectEqual(PhysicalLibrary.builtIn[0].name, "25m")
    expectEqual(PhysicalLibrary.builtIn[0].kind, .chrono)
    expectEqual(PhysicalLibrary.builtIn[0].fixedSeconds, nil)
    expectEqual(PhysicalLibrary.builtIn.last?.name, "1 min aller-retour sprint")
    expectEqual(PhysicalLibrary.builtIn.last?.kind, .duration)
    expectEqual(PhysicalLibrary.builtIn.last?.fixedSeconds, 60)
    expectEqual(PhysicalLibrary.maxNameLength, 30)
    expectEqual(PhysicalLibrary.maxRepsPerAttempt, 50)

    // Codable round trip keeps ids and the optional fields.
    let ex = PhysicalExercise(name: "100m", kind: .chrono)
    let data = try! JSONEncoder().encode(ex)
    let back = try! JSONDecoder().decode(PhysicalExercise.self, from: data)
    expectEqual(back, ex)

    let session = PhysicalSession(exerciseName: "100m", kind: .chrono,
                                   date: Date(timeIntervalSince1970: 1000),
                                   attempts: [PhysicalAttempt(seconds: 14.23, reps: nil)],
                                   sentFromWatch: true)
    let sData = try! JSONEncoder().encode(session)
    let sBack = try! JSONDecoder().decode(PhysicalSession.self, from: sData)
    expectEqual(sBack.attempts, [PhysicalAttempt(seconds: 14.23, reps: nil)])
    expectEqual(sBack.sentFromWatch, true)
}

func testFormat() {
    expectEqual(PhysicalFormat.chronoResult(14.23), "14.23 s")
    expectEqual(PhysicalFormat.chronoResult(-3), "0.00 s")
    expectEqual(PhysicalFormat.repsResult(12), "12 rép.")
    expectEqual(PhysicalFormat.repsResult(-1), "0 rép.")
    expectEqual(PhysicalFormat.duration(45), "45 s")
    expectEqual(PhysicalFormat.duration(60), "1 min")
    expectEqual(PhysicalFormat.duration(90), "1 min 30 s")
    expectEqual(PhysicalFormat.runningClock(0), "0:00.0")
    expectEqual(PhysicalFormat.runningClock(4.9), "0:04.9")
    expectEqual(PhysicalFormat.runningClock(65.0), "1:05.0")
    expectEqual(PhysicalFormat.runningClock(-3), "0:00.0")
}

func testTimer() {
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 0), 60)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 0.1), 60)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 30.0), 30)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 59.9), 1)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 60.0), 0)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 61.0), 0)
    // Negative elapsed (shouldn't happen on a real wall clock) must not overshoot past fixedSeconds.
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: -5), 60)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 59.9), false)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 60.0), true)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 61.0), true)
}

@main
struct PhysicalTests {
    static func main() {
        testModels()
        testFormat()
        testTimer()
        print("Task 1 (physical) assertions passed")
    }
}
```

- [ ] **Step 2: Run it to verify it fails to compile**

```bash
cd ios-app && swiftc Scripts/physical_tests.swift -o "${TMPDIR:-/tmp}/physical_tests"
```
Expected: error — `cannot find type 'PhysicalExercise' in scope` (neither model file exists yet).

- [ ] **Step 3: Implement `Physical.swift`**

```swift
import Foundation

// ─────────────────────────────────────────────────
// EXERCICES PHYSIQUES — modèles purs (aucune dépendance UI)
// ─────────────────────────────────────────────────

enum PhysicalExerciseKind: String, Codable {
    case chrono     // stopwatch: measure elapsed time
    case duration   // fixed-duration countdown: count repetitions
}

struct PhysicalExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: PhysicalExerciseKind
    var fixedSeconds: Int?    // required (5...600, step 5) iff kind == .duration; nil iff kind == .chrono
}

struct PhysicalAttempt: Codable, Equatable {
    var seconds: Double?      // chrono result (e.g. 14.23)
    var reps: Int?            // duration result (repetitions counted)
}

struct PhysicalSession: Codable, Identifiable {
    var id = UUID()
    var exerciseName: String
    var kind: PhysicalExerciseKind
    var date: Date             // session start; (date, exerciseName) dedupes watch re-sends
    var attempts: [PhysicalAttempt]
    var sentFromWatch: Bool
}

enum PhysicalLibrary {
    static let builtIn: [PhysicalExercise] = [
        PhysicalExercise(name: "25m", kind: .chrono),
        PhysicalExercise(name: "50m", kind: .chrono),
        PhysicalExercise(name: "100m", kind: .chrono),
        PhysicalExercise(name: "Suicide", kind: .chrono),
        PhysicalExercise(name: "1 min aller-retour sprint", kind: .duration, fixedSeconds: 60),
    ]
    static let maxNameLength = 30
    static let fixedSecondsRange = 5...600
    static let maxRepsPerAttempt = 50
}

enum PhysicalFormat {
    // "14.23 s" — hundredths of a second, matches typical sprint-time display.
    static func chronoResult(_ seconds: Double) -> String {
        String(format: "%.2f s", max(seconds, 0))
    }

    // "12 rép." (negative clamps to 0)
    static func repsResult(_ reps: Int) -> String {
        "\(max(reps, 0)) rép."
    }

    // "45 s", "1 min", "1 min 30 s" — same style as DribbleFormat.duration.
    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    // Stopwatch / elapsed display while a chrono is running: "m:ss.d"
    static func runningClock(_ seconds: Double) -> String {
        let t = max(seconds, 0)
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }
}
```

- [ ] **Step 4: Implement `PhysicalTimer.swift`**

```swift
import Foundation

// Pure timing helpers for physical exercises — no UI/Timer dependency.
enum PhysicalTimer {
    // Remaining whole seconds for a Durée fixe countdown, ceiling-rounded, clamped to 0.
    static func secondsRemaining(fixedSeconds: Int, elapsed: Double) -> Int {
        let remaining = Double(fixedSeconds) - max(elapsed, 0)
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    static func isFinished(fixedSeconds: Int, elapsed: Double) -> Bool {
        max(elapsed, 0) >= Double(fixedSeconds)
    }
}
```

- [ ] **Step 5: Run the test script to verify it passes**

```bash
cd ios-app && swiftc Models/../Models/Physical.swift BasketTrainer/Models/Physical.swift 2>/dev/null; \
swiftc BasketTrainer/Models/Physical.swift BasketTrainer/Models/PhysicalTimer.swift Scripts/physical_tests.swift -o "${TMPDIR:-/tmp}/physical_tests" && "${TMPDIR:-/tmp}/physical_tests"
```
(Ignore the first line above if your shell complains — it's a no-op guard; the real command is the second one.) Expected: prints `Task 1 (physical) assertions passed`, exit code 0, no compiler warnings.

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Models/Physical.swift ios-app/BasketTrainer/Models/PhysicalTimer.swift ios-app/Scripts/physical_tests.swift
git diff --cached --stat
git commit -m "feat: add physical exercise models, formatting and timer helpers" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `PhysicalStore`, Xcode registration, app injection

**Files:**
- Create: `ios-app/BasketTrainer/Models/PhysicalStore.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`
- Modify: `ios-app/BasketTrainer/BasketTrainerApp.swift`

**Interfaces:**
- Consumes: `PhysicalExercise`, `PhysicalSession`, `PhysicalLibrary.builtIn` (Task 1).
- Produces — `final class PhysicalStore: ObservableObject`:
  - `static let shared`, `static let watchSlotCount = 5`
  - `@Published private(set) var exercises: [PhysicalExercise]` (seeded with `PhysicalLibrary.builtIn` on first launch — no stored value yet; an empty saved array stays empty, nothing re-seeds it), `watchSlots: [PhysicalExercise?]` (always 5 entries), `sessions: [PhysicalSession]`
  - `func save(_ exercise: PhysicalExercise)` (insert or replace by id), `func delete(_ exercise: PhysicalExercise)`
  - `func setWatchSlot(_ index: Int, exercise: PhysicalExercise?)` (ignores out-of-range)
  - `@discardableResult func add(_ session: PhysicalSession) -> Bool` — `false` (not added) on exact `(date, exerciseName)` duplicate
  - `func deleteSession(_ session: PhysicalSession)`
- Environment: `BasketTrainerApp` injects a `PhysicalStore` as an environment object (later views use `@EnvironmentObject var physicalStore: PhysicalStore`).

This task has no `swiftc` test (it depends on `UserDefaults`, same as `DribbleStore`); verification is the build.

- [ ] **Step 1: Create `PhysicalStore.swift`**

```swift
import Foundation
import Combine

// ─────────────────────────────────────────────────
// STORE EXERCICES PHYSIQUES — bibliothèque, emplacements montre, historique.
// Mêmes conventions que DribbleStore/ProfileStore (UserDefaults + Codable).
// ─────────────────────────────────────────────────
final class PhysicalStore: ObservableObject {
    static let shared = PhysicalStore()
    static let watchSlotCount = 5

    @Published private(set) var exercises: [PhysicalExercise] = []
    @Published private(set) var watchSlots: [PhysicalExercise?] = Array(repeating: nil, count: PhysicalStore.watchSlotCount)
    @Published private(set) var sessions: [PhysicalSession] = []

    private let exercisesKey  = "basket_physical_exercises"
    private let watchSlotsKey = "basket_physical_watch_slots"
    private let sessionsKey   = "basket_physical_sessions"

    init() {
        if let v: [PhysicalExercise] = load(exercisesKey) {
            exercises = v
        } else {
            exercises = PhysicalLibrary.builtIn   // premier lancement : pas de valeur stockée encore
        }
        if let v: [PhysicalExercise?] = load(watchSlotsKey), v.count == Self.watchSlotCount { watchSlots = v }
        if let v: [PhysicalSession] = load(sessionsKey) { sessions = v }
    }

    // ── Exercices ──

    func save(_ exercise: PhysicalExercise) {
        if let i = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[i] = exercise
        } else {
            exercises.append(exercise)
        }
        persist(exercises, exercisesKey)
    }

    func delete(_ exercise: PhysicalExercise) {
        exercises.removeAll { $0.id == exercise.id }
        persist(exercises, exercisesKey)
    }

    // ── Emplacements montre (copie de l'exercice au moment de l'envoi) ──

    func setWatchSlot(_ index: Int, exercise: PhysicalExercise?) {
        guard watchSlots.indices.contains(index) else { return }
        watchSlots[index] = exercise
        persist(watchSlots, watchSlotsKey)
    }

    // ── Historique ──

    @discardableResult
    func add(_ session: PhysicalSession) -> Bool {
        // La montre peut renvoyer une séance déjà livrée (callback de fin perdu) — on l'ignore.
        if sessions.contains(where: { $0.date == session.date && $0.exerciseName == session.exerciseName }) {
            return false
        }
        sessions.append(session)
        persist(sessions, sessionsKey)
        return true
    }

    func deleteSession(_ session: PhysicalSession) {
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

- [ ] **Step 2: Register `Physical.swift`, `PhysicalTimer.swift` and `PhysicalStore.swift` in `project.pbxproj`**

UUIDs (verified unused before this plan; `ADE` was the highest used by the Dribble feature):

| File | PBXFileReference UUID | PBXBuildFile UUID |
|---|---|---|
| Physical.swift | `AA0000000000000000000ADF` | `AA0000000000000000000AE0` |
| PhysicalTimer.swift | `AA0000000000000000000AE1` | `AA0000000000000000000AE2` |
| PhysicalStore.swift | `AA0000000000000000000AE3` | `AA0000000000000000000AE4` |

Before editing, run `grep -c "AA0000000000000000000AD[F]\|AA0000000000000000000AE[1-4]" ios-app/BasketTrainer.xcodeproj/project.pbxproj` and confirm `0`. Then make four insertions (tab-indented like neighbours):

1. In the `PBXBuildFile` section, after the line containing `DribbleHomeView.swift in Sources */ = {isa = PBXBuildFile;`, add:
```
		AA0000000000000000000AE0 /* Physical.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000ADF /* Physical.swift */; };
		AA0000000000000000000AE2 /* PhysicalTimer.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AE1 /* PhysicalTimer.swift */; };
		AA0000000000000000000AE4 /* PhysicalStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AE3 /* PhysicalStore.swift */; };
```
2. In the `PBXFileReference` section, after the line containing `/* DribbleHomeView.swift */ = {isa = PBXFileReference;`, add:
```
		AA0000000000000000000ADF /* Physical.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Physical.swift; sourceTree = "<group>"; };
		AA0000000000000000000AE1 /* PhysicalTimer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalTimer.swift; sourceTree = "<group>"; };
		AA0000000000000000000AE3 /* PhysicalStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalStore.swift; sourceTree = "<group>"; };
```
3. In the **Models** `PBXGroup` children list (the one that ends with `AA0000000000000000000AD5 /* DribbleStore.swift */,` followed by a closing `);`), after that `DribbleStore.swift` line, add:
```
				AA0000000000000000000ADF /* Physical.swift */,
				AA0000000000000000000AE1 /* PhysicalTimer.swift */,
				AA0000000000000000000AE3 /* PhysicalStore.swift */,
```
4. In the target's `PBXSourcesBuildPhase` `files` list, after the line `AA0000000000000000000ADE /* DribbleHomeView.swift in Sources */,`, add:
```
				AA0000000000000000000AE0 /* Physical.swift in Sources */,
				AA0000000000000000000AE2 /* PhysicalTimer.swift in Sources */,
				AA0000000000000000000AE4 /* PhysicalStore.swift in Sources */,
```

Verify: `plutil -lint ios-app/BasketTrainer.xcodeproj/project.pbxproj` prints `OK`; each fileRef UUID (`ADF`,`AE1`,`AE3`) appears exactly 3 times and each build-file UUID (`AE0`,`AE2`,`AE4`) exactly 2 times.

- [ ] **Step 3: Inject the store in `BasketTrainerApp.swift`**

Add the state object after `@StateObject private var dribbleStore = DribbleStore.shared`:
```swift
    @StateObject private var physicalStore = PhysicalStore.shared
```
and add, after `.environmentObject(dribbleStore)`:
```swift
                .environmentObject(physicalStore)
```

- [ ] **Step 4: Build to verify**

Run the build verification command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Models/PhysicalStore.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj ios-app/BasketTrainer/BasketTrainerApp.swift
git diff --cached --stat
git commit -m "feat: add PhysicalStore and register physical model files" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Exercise editor view

**Files:**
- Create: `ios-app/BasketTrainer/Views/PhysicalExerciseEditorView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PhysicalStore.save` via `@EnvironmentObject var physicalStore: PhysicalStore`; `PhysicalExercise`, `PhysicalExerciseKind`, `PhysicalLibrary.maxNameLength`/`fixedSecondsRange`, `PhysicalFormat.duration` (Task 1).
- Produces: `struct PhysicalExerciseEditorView: View` with `init(exercise: PhysicalExercise?)` — `nil` creates a new exercise (new `UUID`, kind picker enabled), non-nil edits it (same `id`, kind picker **disabled** — the kind is fixed at creation per Global Constraints). On save it calls `physicalStore.save(...)` and dismisses. Presented as a sheet by Task 6.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR D'EXERCICE PHYSIQUE — nom, type (chrono ou durée fixe),
// et la durée fixe si applicable. Le type n'est modifiable qu'à la
// création : pour un exercice existant, le picker est désactivé.
// ─────────────────────────────────────────────────
struct PhysicalExerciseEditorView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @Environment(\.dismiss) var dismiss

    private let exerciseID: UUID
    private let isNew: Bool
    @State private var name: String
    @State private var kind: PhysicalExerciseKind
    @State private var fixedSeconds: Int

    init(exercise: PhysicalExercise?) {
        exerciseID = exercise?.id ?? UUID()
        isNew = exercise == nil
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .chrono)
        _fixedSeconds = State(initialValue: exercise?.fixedSeconds ?? 60)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. 100m, Suicide...", text: $name)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Chrono").tag(PhysicalExerciseKind.chrono)
                        Text("Durée fixe").tag(PhysicalExerciseKind.duration)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isNew)

                    if kind == .duration {
                        Stepper(PhysicalFormat.duration(fixedSeconds),
                                value: $fixedSeconds,
                                in: PhysicalLibrary.fixedSecondsRange,
                                step: 5)
                    }
                } header: {
                    Text("Type")
                } footer: {
                    if !isNew {
                        Text("Le type ne peut pas être changé après la création.")
                    } else if kind == .chrono {
                        Text("Tu lanceras un chrono et l'arrêteras à la fin de l'exercice.")
                    } else {
                        Text("Un compte à rebours de cette durée se lance, puis tu indiques le nombre de répétitions faites.")
                    }
                }
            }
            .navigationTitle(isNew ? "Nouvel exercice" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(PhysicalLibrary.maxNameLength))
        let exercise = PhysicalExercise(
            id: exerciseID,
            name: trimmed,
            kind: kind,
            fixedSeconds: kind == .duration ? fixedSeconds : nil
        )
        physicalStore.save(exercise)
        dismiss()
    }
}
```

- [ ] **Step 2: Register `PhysicalExerciseEditorView.swift` in `project.pbxproj`**

UUIDs (verify unused with `grep -c "AA0000000000000000000AE[56]"` → `0`): fileRef `AA0000000000000000000AE5`, buildFile `AA0000000000000000000AE6`. Four insertions:

1. `PBXBuildFile` — after the line containing `PhysicalStore.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000AE6 /* PhysicalExerciseEditorView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AE5 /* PhysicalExerciseEditorView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* PhysicalStore.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000AE5 /* PhysicalExerciseEditorView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalExerciseEditorView.swift; sourceTree = "<group>"; };
```
3. **Views** `PBXGroup` children (the group containing `/* DribbleHomeView.swift */,`) — after that line:
```
				AA0000000000000000000AE5 /* PhysicalExerciseEditorView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000AE4 /* PhysicalStore.swift in Sources */,`:
```
				AA0000000000000000000AE6 /* PhysicalExerciseEditorView.swift in Sources */,
```
Verify with `plutil -lint` → `OK`; `AE5` appears exactly 3×, `AE6` exactly 2×.

- [ ] **Step 3: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`, no new warnings from `PhysicalExerciseEditorView.swift`.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/PhysicalExerciseEditorView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add physical exercise editor" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Run view (phone) — chrono, countdown, attempts, summary

**Files:**
- Create: `ios-app/BasketTrainer/Views/PhysicalRunView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PhysicalTimer.secondsRemaining/isFinished` (Task 1); `PhysicalExercise`, `PhysicalAttempt`, `PhysicalSession`, `PhysicalFormat.chronoResult/repsResult/duration/runningClock`, `PhysicalLibrary.maxRepsPerAttempt` (Task 1); `PhysicalStore.add` (Task 2) via `@EnvironmentObject`.
- Produces: `struct PhysicalRunView: View` with `init(exercise: PhysicalExercise)`. Repeats attempts live (0.25s tick on wall-clock `Date`), haptic + system sound when a countdown ends, keeps the screen awake, shows a running list of attempts, and a summary at the end with "Enregistrer" (adds a `PhysicalSession` with `sentFromWatch: false`) and "Quitter". Presented full-screen by Task 6.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import AudioToolbox
import UIKit

// ─────────────────────────────────────────────────
// EXERCICE PHYSIQUE (iPhone) — chrono (temps mesuré) ou minuteur à
// durée fixe (répétitions comptées). Horloge murale (Date), comme
// les routines de dribble : pas de dérive si l'app ralentit.
// ─────────────────────────────────────────────────
struct PhysicalRunView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @Environment(\.dismiss) var dismiss

    let exercise: PhysicalExercise

    private enum Phase: Equatable {
        case idle            // prêt pour la prochaine tentative
        case runningChrono   // chrono en cours
        case countdown       // compte à rebours (durée fixe)
        case enteringReps    // compte à rebours terminé, saisie des répétitions
        case summary         // séance terminée, récapitulatif + enregistrement
    }

    @State private var phase: Phase = .idle
    @State private var attempts: [PhysicalAttempt] = []
    @State private var sessionStart = Date()
    @State private var attemptStart = Date()
    @State private var elapsed: Double = 0
    @State private var repsInput = 0
    @State private var showQuitConfirm = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                switch phase {
                case .idle:            idleContent
                case .runningChrono:   chronoContent
                case .countdown:       countdownContent
                case .enteringReps:    repsContent
                case .summary:         summaryContent
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        if attempts.isEmpty || phase == .summary { dismiss() } else { showQuitConfirm = true }
                    }
                    .foregroundStyle(.orange)
                }
            }
            .alert("Quitter sans enregistrer ?", isPresented: $showQuitConfirm) {
                Button("Continuer", role: .cancel) {}
                Button("Quitter", role: .destructive) { dismiss() }
            } message: {
                Text("Les tentatives déjà faites ne seront pas enregistrées.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { _ in tick() }
    }

    // ── Déroulement ──

    private func tick() {
        guard phase == .runningChrono || phase == .countdown else { return }
        elapsed = Date().timeIntervalSince(attemptStart)
        if phase == .countdown, let fixed = exercise.fixedSeconds,
           PhysicalTimer.isFinished(fixedSeconds: fixed, elapsed: elapsed) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
            repsInput = 0
            phase = .enteringReps
        }
    }

    private func startAttempt() {
        if attempts.isEmpty { sessionStart = Date() }
        attemptStart = Date()
        elapsed = 0
        phase = exercise.kind == .duration ? .countdown : .runningChrono
    }

    private func stopChrono() {
        let exact = Date().timeIntervalSince(attemptStart)
        attempts.append(PhysicalAttempt(seconds: exact, reps: nil))
        phase = .idle
    }

    private func confirmReps() {
        attempts.append(PhysicalAttempt(seconds: nil, reps: repsInput))
        phase = .idle
    }

    // ── Écrans ──

    private var idleContent: some View {
        VStack(spacing: 28) {
            attemptsList
            Spacer()
            VStack(spacing: 10) {
                Text(exercise.kind == .chrono ? "Prêt pour le chrono" : "Prêt pour le minuteur")
                    .font(.headline)
                if exercise.kind == .duration, let fixed = exercise.fixedSeconds {
                    Text(PhysicalFormat.duration(fixed))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                startAttempt()
            } label: {
                Text(attempts.isEmpty ? "Démarrer" : "Nouvelle tentative")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)

            if !attempts.isEmpty {
                Button("Terminer") { phase = .summary }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 20)
        }
        .padding(.top, 16)
    }

    private var chronoContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(PhysicalFormat.runningClock(elapsed))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Spacer()
            Button {
                stopChrono()
            } label: {
                Text("Arrêter")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var countdownContent: some View {
        let fixed = exercise.fixedSeconds ?? 0
        let remaining = PhysicalTimer.secondsRemaining(fixedSeconds: fixed, elapsed: elapsed)
        return VStack(spacing: 28) {
            Spacer()
            Text("\(remaining)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(remaining <= 3 ? Color.red : Color.primary)
            Text("secondes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var repsContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Combien de répétitions ?")
                .font(.headline)
            Text("\(repsInput)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            Stepper("", value: $repsInput, in: 0...PhysicalLibrary.maxRepsPerAttempt)
                .labelsHidden()
            Spacer()
            Button {
                confirmReps()
            } label: {
                Text("Valider")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var attemptsList: some View {
        Group {
            if !attempts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tentatives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    ForEach(attempts.indices, id: \.self) { i in
                        HStack {
                            Text("#\(i + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(attemptLabel(attempts[i]))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func attemptLabel(_ attempt: PhysicalAttempt) -> String {
        if let s = attempt.seconds { return PhysicalFormat.chronoResult(s) }
        if let r = attempt.reps { return PhysicalFormat.repsResult(r) }
        return "—"
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("🎉").font(.system(size: 44))
                    Text("Séance terminée")
                        .font(.title3.bold())
                    Text("\(attempts.count) tentative\(attempts.count > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    ForEach(attempts.indices, id: \.self) { i in
                        HStack {
                            Text("Tentative \(i + 1)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(attemptLabel(attempts[i]))
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
        physicalStore.add(PhysicalSession(
            exerciseName: exercise.name,
            kind: exercise.kind,
            date: sessionStart,
            attempts: attempts,
            sentFromWatch: false
        ))
        dismiss()
    }
}
```

- [ ] **Step 2: Register `PhysicalRunView.swift` in `project.pbxproj`**

UUIDs (verify unused: `grep -c "AA0000000000000000000AE[78]"` → `0`): fileRef `AA0000000000000000000AE7`, buildFile `AA0000000000000000000AE8`. Same four insertions as Task 3, chained after the editor's lines:

1. `PBXBuildFile` — after the line containing `PhysicalExerciseEditorView.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000AE8 /* PhysicalRunView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AE7 /* PhysicalRunView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* PhysicalExerciseEditorView.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000AE7 /* PhysicalRunView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalRunView.swift; sourceTree = "<group>"; };
```
3. **Views** group children — after `AA0000000000000000000AE5 /* PhysicalExerciseEditorView.swift */,`:
```
				AA0000000000000000000AE7 /* PhysicalRunView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000AE6 /* PhysicalExerciseEditorView.swift in Sources */,`:
```
				AA0000000000000000000AE8 /* PhysicalRunView.swift in Sources */,
```
Verify `plutil -lint` → `OK`; `AE7` 3×, `AE8` 2×.

- [ ] **Step 3: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/PhysicalRunView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add physical exercise run view (chrono and countdown)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Phone side of the watch link (`GarminManager`)

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

**Interfaces:**
- Consumes: `PhysicalExercise`, `PhysicalSession`, `PhysicalAttempt`, `PhysicalExerciseKind` (Task 1); `PhysicalStore.shared.add` (Task 2).
- Produces:
  - `@Published var lastPhysicalSlotSendMessage: String?` (same role as `lastDribbleSlotSendMessage`)
  - `func sendPhysicalSlot(_ index: Int, exercise: PhysicalExercise)` — same wake-then-send pattern as `sendDribbleSlot`, message `{"type": "physicalSlot", "index": Int, "name": String, "kind": String ("chrono"|"duration"), "seconds": Int}` — the `"seconds"` key is **absent** when the exercise is `.chrono` (not sent as `null`; the key itself is omitted).
  - `receivedMessage` routes `{"type": "physicalSession", ...}` to `PhysicalStore` (`sentFromWatch: true`); the existing `dribbleSession` routing and the no-`type` shooting path are unchanged.

- [ ] **Step 1: Add the published message property**

After `@Published var lastDribbleSlotSendMessage: String? = nil` add:
```swift
    @Published var lastPhysicalSlotSendMessage: String? = nil
```

- [ ] **Step 2: Route incoming messages by type, and add the parser**

Replace the body of `receivedMessage`:
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
```
with:
```swift
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        // Les séances de tirs n'ont pas de clé "type" — elles gardent leur chemin habituel.
        let type = dict["type"] as? String
        if type == "dribbleSession" {
            parseDribbleSession(dict)
            return
        }
        if type == "physicalSession" {
            parsePhysicalSession(dict)
            return
        }
        parseAndStore(dict)
    }

    private func parsePhysicalSession(_ dict: [String: Any]) {
        let exerciseName = dict["exerciseName"] as? String ?? "Exercice"
        guard let kindRaw = dict["kind"] as? String, let kind = PhysicalExerciseKind(rawValue: kindRaw) else {
            print("parsePhysicalSession → kind absent ou invalide, séance ignorée")
            return
        }
        guard let startTime = dict["startTime"] as? Int, startTime > 0 else {
            print("parsePhysicalSession → startTime absent ou invalide, séance ignorée")
            return
        }
        let rawAttempts = dict["attempts"] as? [[String: Any]] ?? []
        let attempts = rawAttempts.map { entry -> PhysicalAttempt in
            let seconds = entry["seconds"] as? Double
            let reps = entry["reps"] as? Int
            return PhysicalAttempt(seconds: seconds, reps: reps)
        }
        let session = PhysicalSession(
            exerciseName: exerciseName,
            kind: kind,
            date: Date(timeIntervalSince1970: TimeInterval(startTime)),
            attempts: attempts,
            sentFromWatch: true
        )
        DispatchQueue.main.async {
            PhysicalStore.shared.add(session)   // ignore un renvoi identique de la montre
        }
    }
```

Leave `parseDribbleSession` and `parseAndStore` byte-for-byte unchanged — only the dispatch at the top of `receivedMessage` and the new `parsePhysicalSession` function are new.

- [ ] **Step 3: Add `sendPhysicalSlot`**

Insert before `func addMockSession() {`:
```swift
    func sendPhysicalSlot(_ index: Int, exercise: PhysicalExercise) {
        guard let device = connectedDevice else {
            lastPhysicalSlotSendMessage = "Montre non connectée"
            return
        }
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        var payload: [String: Any] = [
            "type": "physicalSlot",
            "index": index,
            "name": exercise.name,
            "kind": exercise.kind.rawValue
        ]
        if let seconds = exercise.fixedSeconds {
            payload["seconds"] = seconds
        }
        sdk.openAppRequest(app) { [weak self] _ in
            self?.sdk.sendMessage(payload, to: app, progress: nil) { result in
                print("sendPhysicalSlot(\(index)) → \(NSStringFromSendMessageResult(result))")
                DispatchQueue.main.async {
                    self?.lastPhysicalSlotSendMessage = result == .success
                        ? "Exercice envoyé à la montre ✅"
                        : "Échec de l'envoi : \(NSStringFromSendMessageResult(result))"
                }
            }
        }
    }
```

- [ ] **Step 4: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`. Manually confirm by reading the diff that (a) `parseAndStore` and `parseDribbleSession` are byte-for-byte unchanged and (b) a dictionary with no `type` key, or `type == "dribbleSession"`, still reaches its existing path.

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git diff --cached --stat
git commit -m "feat: send physical exercises to the watch and receive physical sessions" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Physical home, history views and Home entry point

**Files:**
- Create: `ios-app/BasketTrainer/Views/PhysicalHomeView.swift`
- Create: `ios-app/BasketTrainer/Views/PhysicalHistoryView.swift`
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PhysicalStore` (`exercises`, `watchSlots`, `sessions`, `delete`, `setWatchSlot`, `deleteSession`), `GarminManager.sendPhysicalSlot` / `lastPhysicalSlotSendMessage` (Task 5), `PhysicalExerciseEditorView(exercise:)` (Task 3), `PhysicalRunView(exercise:)` (Task 4), `PhysicalFormat` (Task 1). Both stores/managers come from `@EnvironmentObject`.
- Produces: `struct PhysicalHomeView: View` (sheet root, own `NavigationStack`), `struct PhysicalHistoryView: View` + `struct PhysicalSessionDetailView: View`, and a "Physique" button on `HomeView`.

- [ ] **Step 1: Create `PhysicalHomeView.swift`**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// PHYSIQUE — bibliothèque d'exercices : lancer, modifier, envoyer à la montre.
// ─────────────────────────────────────────────────
private struct PhysicalEditorTarget: Identifiable {
    let id = UUID()
    let exercise: PhysicalExercise?      // nil = nouvel exercice
}

struct PhysicalHomeView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editorTarget: PhysicalEditorTarget? = nil
    @State private var runningExercise: PhysicalExercise? = nil

    var body: some View {
        NavigationStack {
            Group {
                if physicalStore.exercises.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(physicalStore.exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Physique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        PhysicalHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button {
                        editorTarget = PhysicalEditorTarget(exercise: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                PhysicalExerciseEditorView(exercise: target.exercise)
            }
            .fullScreenCover(item: $runningExercise) { exercise in
                PhysicalRunView(exercise: exercise)
            }
            .alert("Envoi à la montre", isPresented: Binding(
                get: { garmin.lastPhysicalSlotSendMessage != nil },
                set: { if !$0 { garmin.lastPhysicalSlotSendMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garmin.lastPhysicalSlotSendMessage ?? "")
            }
        }
    }

    private func exerciseRow(_ exercise: PhysicalExercise) -> some View {
        HStack(spacing: 12) {
            Button {
                runningExercise = exercise
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(kindLabel(exercise))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
            .buttonStyle(.borderless)

            Menu {
                Button("Modifier") { editorTarget = PhysicalEditorTarget(exercise: exercise) }
                Menu("Envoyer à la montre") {
                    ForEach(0..<PhysicalStore.watchSlotCount, id: \.self) { i in
                        Button("Emplacement \(i + 1) — \(physicalStore.watchSlots[i]?.name ?? "vide")") {
                            physicalStore.setWatchSlot(i, exercise: exercise)
                            garmin.sendPhysicalSlot(i, exercise: exercise)
                        }
                    }
                }
                Button("Supprimer", role: .destructive) { physicalStore.delete(exercise) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func kindLabel(_ exercise: PhysicalExercise) -> String {
        switch exercise.kind {
        case .chrono:
            return "Chrono"
        case .duration:
            let seconds = exercise.fixedSeconds ?? 0
            return "Durée fixe · \(PhysicalFormat.duration(seconds))"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏃").font(.system(size: 52))
            Text("Aucun exercice")
                .font(.title3.bold())
            Text("Ajoute un exercice chronométré (25m, 100m, suicide...) ou à durée fixe (1 min aller-retour...).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                editorTarget = PhysicalEditorTarget(exercise: nil)
            } label: {
                Label("Ajouter un exercice", systemImage: "plus.circle.fill")
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

- [ ] **Step 2: Create `PhysicalHistoryView.swift`**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// HISTORIQUE EXERCICES PHYSIQUES — séances terminées (téléphone ou montre).
// Séparé de l'historique de tirs et de celui de dribble.
// ─────────────────────────────────────────────────
struct PhysicalHistoryView: View {
    @EnvironmentObject var physicalStore: PhysicalStore

    private var sorted: [PhysicalSession] {
        physicalStore.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                VStack(spacing: 10) {
                    Text("Aucune séance physique")
                        .font(.headline)
                    Text("Les exercices terminés apparaissent ici.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(sorted) { session in
                        NavigationLink {
                            PhysicalSessionDetailView(session: session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.exerciseName).font(.headline)
                                        if session.sentFromWatch { Text("⌚").font(.caption2) }
                                    }
                                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(session.attempts.count) tentative\(session.attempts.count > 1 ? "s" : "")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { physicalStore.deleteSession(sorted[i]) }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Historique physique")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PhysicalSessionDetailView: View {
    let session: PhysicalSession

    var body: some View {
        List {
            Section {
                row("Date", session.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                row("Type", session.kind == .chrono ? "Chrono" : "Durée fixe")
                row("Source", session.sentFromWatch ? "Montre" : "iPhone")
            }
            Section("Tentatives") {
                if session.attempts.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }
                ForEach(session.attempts.indices, id: \.self) { i in
                    row("Tentative \(i + 1)", attemptLabel(session.attempts[i]))
                }
            }
        }
        .navigationTitle(session.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func attemptLabel(_ attempt: PhysicalAttempt) -> String {
        if let s = attempt.seconds { return PhysicalFormat.chronoResult(s) }
        if let r = attempt.reps { return PhysicalFormat.repsResult(r) }
        return "—"
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
    case dribble
    case slotsConfig
```
to
```swift
    case dribble
    case physical
    case slotsConfig
```
and, in `var id`, after `case .dribble:         return "dribble"` add:
```swift
        case .physical:        return "physical"
```
(b) In the `.sheet(item: $activeSheet)` switch, after
```swift
                case .dribble:
                    DribbleHomeView()
```
add:
```swift
                case .physical:
                    PhysicalHomeView()
```
(c) Show the button under the existing dribble button: change
```swift
                        dribbleButton
                            .padding(.horizontal, 20)

                        if !store.recentSessions.isEmpty {
```
to
```swift
                        dribbleButton
                            .padding(.horizontal, 20)

                        physicalButton
                            .padding(.horizontal, 20)

                        if !store.recentSessions.isEmpty {
```
and add this property right after the `dribbleButton` property definition (i.e. after its closing `}`, before `private var recentSessionsList: some View {`):
```swift
    private var physicalButton: some View {
        Button {
            activeSheet = .physical
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "figure.run")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Physique")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Sprints et exercices chronométrés, sur le tél. ou la montre")
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

UUIDs (verify unused: `grep -c "AA0000000000000000000AE[9A]\|AA0000000000000000000AE[BC]"` → `0`):

| File | fileRef | buildFile |
|---|---|---|
| PhysicalHistoryView.swift | `AA0000000000000000000AE9` | `AA0000000000000000000AEA` |
| PhysicalHomeView.swift | `AA0000000000000000000AEB` | `AA0000000000000000000AEC` |

Insertions (same four places as before, chained after the Run view's lines):
1. `PBXBuildFile` — after the line containing `PhysicalRunView.swift in Sources */ = {isa = PBXBuildFile;`:
```
		AA0000000000000000000AEA /* PhysicalHistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AE9 /* PhysicalHistoryView.swift */; };
		AA0000000000000000000AEC /* PhysicalHomeView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000AEB /* PhysicalHomeView.swift */; };
```
2. `PBXFileReference` — after the line containing `/* PhysicalRunView.swift */ = {isa = PBXFileReference;`:
```
		AA0000000000000000000AE9 /* PhysicalHistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalHistoryView.swift; sourceTree = "<group>"; };
		AA0000000000000000000AEB /* PhysicalHomeView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhysicalHomeView.swift; sourceTree = "<group>"; };
```
3. **Views** group children — after `AA0000000000000000000AE7 /* PhysicalRunView.swift */,`:
```
				AA0000000000000000000AE9 /* PhysicalHistoryView.swift */,
				AA0000000000000000000AEB /* PhysicalHomeView.swift */,
```
4. `PBXSourcesBuildPhase` — after `AA0000000000000000000AE8 /* PhysicalRunView.swift in Sources */,`:
```
				AA0000000000000000000AEA /* PhysicalHistoryView.swift in Sources */,
				AA0000000000000000000AEC /* PhysicalHomeView.swift in Sources */,
```
Verify `plutil -lint` → `OK`; `AE9`,`AEB` 3× each; `AEA`,`AEC` 2× each.

- [ ] **Step 5: Build to verify**

Run the build verification command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Views/PhysicalHomeView.swift ios-app/BasketTrainer/Views/PhysicalHistoryView.swift ios-app/BasketTrainer/Views/HomeView.swift ios-app/BasketTrainer.xcodeproj/project.pbxproj
git diff --cached --stat
git commit -m "feat: add physical home, history and Home entry point" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Watch — store incoming physical slots (`BasketApp.mc`)

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`

**Interfaces:**
- Consumes: the phone message `{"type": "physicalSlot", "index", "name", "kind", "seconds"?}` (Task 5).
- Produces: `Application.Storage` key `"physicalSlot_<0-4>"` holding `{"name" => String, "kind" => String ("chrono"|"duration"), "seconds" => Number or null}`. Task 8 reads this exact shape.

A Connect IQ SDK and compiler **are** available in this environment (see Global Constraints) — this task's change is compile-verified here with `monkeyc`, not only inspected. It is still not run on a real device.

- [ ] **Step 1: Add the `physicalSlot` branch**

In `onPhoneAppMessage`, immediately **before** the line
```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("customSpots")) {
```
insert:
```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("physicalSlot")) {
            var pSlot = dict["index"];
            if (!(pSlot instanceof Number || pSlot instanceof Long) || pSlot < 0 || pSlot > 4) { return; }
            if (!(dict["name"] instanceof String) || !(dict["kind"] instanceof String)) { return; }
            var pKind = dict["kind"] as String;
            if (!pKind.equals("chrono") && !pKind.equals("duration")) { return; }
            if (pKind.equals("duration")) {
                var pSeconds = dict["seconds"];
                if (!(pSeconds instanceof Number || pSeconds instanceof Long) || pSeconds < 5) { return; }
                Application.Storage.setValue("physicalSlot_" + pSlot.toString(),
                    { "name" => dict["name"], "kind" => pKind, "seconds" => pSeconds.toNumber() });
            } else {
                Application.Storage.setValue("physicalSlot_" + pSlot.toString(),
                    { "name" => dict["name"], "kind" => pKind, "seconds" => null });
            }
        }
```

- [ ] **Step 2: Compile to verify**

```bash
cd garmin-app && "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" -d fr255 -f monkey.jungle -o "${TMPDIR:-/tmp}/physical-check.prg" -y developer_key -w
```
Expected: `BUILD SUCCESSFUL`, with only the pre-existing `_sync` unused-variable warning.

- [ ] **Step 3: Commit**

```bash
git add garmin-app/source/BasketApp.mc
git diff --cached --stat
git commit -m "feat(watch): store physical exercise slots received from the phone" -m "Compile-verified with monkeyc (BUILD SUCCESSFUL); not run on a real device." -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Watch — Physique menu, run view and MainMenu entry

**Files:**
- Create: `garmin-app/source/PhysicalMenu.mc`
- Create: `garmin-app/source/PhysicalView.mc`
- Modify: `garmin-app/source/MainMenu.mc`

**Interfaces:**
- Consumes: `Application.Storage` keys `physicalSlot_<i>` (Task 7).
- Produces: a fifth main-menu entry "Physique" (id 4) → `PhysicalSlotMenuView` (5 slots) → `PhysicalRun`/`PhysicalRunView`/`PhysicalRunDelegate`. `class PhysicalRun`, `class PhysicalRunView extends WatchUi.View`, `class PhysicalRunDelegate extends WatchUi.BehaviorDelegate`, and global helpers `physicalVibe(Number)`, `physicalFit(dc, text, font, maxWidth) as String`, `physicalClock(Double) as String`. `PhysicalRun.toDictionary()` produces the watch→phone message `{"type": "physicalSession", "exerciseName", "kind", "startTime", "attempts": [{"seconds"} | {"reps"}]}` that `GarminManager.parsePhysicalSession` reads (Task 5).

`PhysicalMenu.mc`'s `onSelect` constructs a `PhysicalRun`/`PhysicalRunView`/`PhysicalRunDelegate` directly, so the menu and the run view are too tightly coupled to split into separate tasks (neither compiles alone) — this mirrors how the Dribble feature's menu and timer view were built as a single task. Build all three files in one pass, then compile once.

Button mapping (mirrors `GoalDelegate`'s `onNextPage`/`onPreviousPage` idiom used elsewhere in this codebase for incrementing a counter):
- **Chrono exercise:** UP starts the stopwatch from idle, or stops it and records the attempt if running. BACK ends the session (transmitting if there is at least one attempt) and pops.
- **Durée fixe exercise:** UP starts the countdown from idle; a vibration fires when it ends and the screen moves to entering a rep count; while entering reps, UP increments and DOWN decrements the count (capped at `PHYS_MAX_REPS = 50`, matching the phone's `PhysicalLibrary.maxRepsPerAttempt`); SELECT confirms the attempt and immediately restarts the countdown. BACK ends the session (transmitting if there is at least one attempt) and pops.
- There is no pause/skip during a running chrono or countdown — same rule as Dribble.

This task's code was drafted and compiled together in this environment before being written into this plan (verified `BUILD SUCCESSFUL`); implement it exactly as below and re-verify with the same `monkeyc` command.

- [ ] **Step 1: Create `PhysicalMenu.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

// ─────────────────────────────────────────────────
// MENU PHYSIQUE — 5 emplacements d'exercices reçus du téléphone
// ─────────────────────────────────────────────────

class PhysicalSlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Physique"});
        for (var i = 0; i < 5; i++) {
            var def   = Application.Storage.getValue("physicalSlot_" + i.toString());
            var label = "Exercice " + (i + 1).toString();
            var sub   = "vide";
            if (def instanceof Dictionary && def["name"] instanceof String && def["kind"] instanceof String) {
                label = def["name"] as String;
                var kind = def["kind"] as String;
                if (kind.equals("duration") && def["seconds"] instanceof Number) {
                    sub = "Duree fixe " + (def["seconds"] as Number).toString() + "s";
                } else {
                    sub = "Chrono";
                }
            }
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class PhysicalSlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId() as Number;
        var def   = Application.Storage.getValue("physicalSlot_" + index.toString());
        if (!(def instanceof Dictionary) || !(def["kind"] instanceof String)) { return; }
        var run  = new PhysicalRun(def as Dictionary);
        var view = new PhysicalRunView(run);
        var del  = new PhysicalRunDelegate(run);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

- [ ] **Step 2: Add the "Physique" entry to `MainMenu.mc`**

In `MainMenuView.initialize`, after
```monkeyc
        addItem(new WatchUi.MenuItem("Dribble",           null, 3, null));
```
add:
```monkeyc
        addItem(new WatchUi.MenuItem("Physique",          null, 4, null));
```
In `MainMenuDelegate.onSelect`, replace the final branch
```monkeyc
        } else if (id == 3) {
            var menu = new DribbleSlotMenuView();
            var del  = new DribbleSlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
```
with
```monkeyc
        } else if (id == 3) {
            var menu = new DribbleSlotMenuView();
            var del  = new DribbleSlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else if (id == 4) {
            var menu = new PhysicalSlotMenuView();
            var del  = new PhysicalSlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
```

- [ ] **Step 3: Create `PhysicalView.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.Attention;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// EXERCICE PHYSIQUE SUR LA MONTRE — chrono (HAUT démarre/arrête) ou
// minuteur à durée fixe (HAUT démarre, puis HAUT/BAS comptent les
// répétitions, SELECT valide et relance). Horloge murale (Time.now).
// ─────────────────────────────────────────────────

const PHYS_IDLE          = 0;
const PHYS_RUNNING       = 1;
const PHYS_COUNTDOWN     = 2;
const PHYS_ENTERING_REPS = 3;
const PHYS_MAX_REPS      = 50;

function physicalVibe(durationMs as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(100, durationMs)]);
    }
}

// Shortens text with ".." so it fits maxWidth pixels on the round display.
function physicalFit(dc as Graphics.Dc, text as String, font as Graphics.FontType,
                      maxWidth as Number) as String {
    if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }
    var len = text.length();
    while (len > 0) {
        len--;
        var candidate = text.substring(0, len) + "..";
        if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) { return candidate; }
    }
    return "..";
}

// "m:ss" — whole seconds only (the phone shows a decimal, the watch keeps it simple).
function physicalClock(elapsed as Double) as String {
    var t = elapsed.toNumber();
    if (t < 0) { t = 0; }
    var m = t / 60;
    var s = t % 60;
    return m.toString() + ":" + s.format("%02d");
}

class PhysicalRun {
    var name         as String;
    var kind         as String;    // "chrono" or "duration"
    var fixedSeconds as Number;    // only meaningful when kind == "duration"
    var startTime    as Number;    // unix seconds, set once when the run starts
    var attempts     as Array;     // [{"seconds" => Double} or {"reps" => Number}]

    var phase        as Number;    // PHYS_*
    var attemptStart as Number;    // unix seconds when the current chrono/countdown attempt began
    var repsInput    as Number;

    function initialize(def as Dictionary) {
        name         = def["name"] as String;
        kind         = def["kind"] as String;
        fixedSeconds = (def["seconds"] instanceof Number) ? def["seconds"] as Number : 0;
        startTime    = Time.now().value();
        attempts     = [];
        phase        = PHYS_IDLE;
        attemptStart = 0;
        repsInput    = 0;
    }

    function elapsedInAttempt() as Double {
        var e = Time.now().value() - attemptStart;
        return (e < 0) ? 0.0 : e.toDouble();
    }

    // HAUT
    function onUp() as Void {
        if (phase == PHYS_IDLE) {
            attemptStart = Time.now().value();
            phase = kind.equals("duration") ? PHYS_COUNTDOWN : PHYS_RUNNING;
        } else if (phase == PHYS_RUNNING) {
            attempts.add({ "seconds" => elapsedInAttempt() });
            phase = PHYS_IDLE;
        } else if (phase == PHYS_ENTERING_REPS) {
            if (repsInput < PHYS_MAX_REPS) { repsInput++; }
        }
        // phase == PHYS_COUNTDOWN: no-op — no pause/skip, same rule as Dribble.
    }

    // BAS
    function onDown() as Void {
        if (phase == PHYS_ENTERING_REPS && repsInput > 0) {
            repsInput--;
        }
    }

    // SELECT — only meaningful while entering a rep count
    function onConfirm() as Void {
        if (phase != PHYS_ENTERING_REPS) { return; }
        attempts.add({ "reps" => repsInput });
        repsInput     = 0;
        attemptStart  = Time.now().value();
        phase         = PHYS_COUNTDOWN;   // relance automatiquement le minuteur
    }

    // Appelé chaque seconde ; renvoie true si le compte à rebours vient de
    // se terminer (pour déclencher la vibration côté vue).
    function tick() as Boolean {
        if (phase == PHYS_COUNTDOWN && elapsedInAttempt() >= fixedSeconds) {
            phase = PHYS_ENTERING_REPS;
            return true;
        }
        return false;
    }

    // Secondes restantes, arrondies au-dessus (même principe que le téléphone).
    function secondsLeft() as Number {
        var remaining = fixedSeconds.toDouble() - elapsedInAttempt();
        if (remaining <= 0) { return 0; }
        var whole = remaining.toNumber();
        if (remaining > whole) { whole = whole + 1; }
        return whole;
    }

    function hasAttempts() as Boolean {
        return attempts.size() > 0;
    }

    function toDictionary() as Dictionary {
        return {
            "type"         => "physicalSession",
            "exerciseName" => name,
            "kind"         => kind,
            "startTime"    => startTime,
            "attempts"     => attempts
        };
    }
}

class PhysicalRunView extends WatchUi.View {
    private var _run   as PhysicalRun;
    private var _timer as Timer.Timer or Null;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_RED    = 0xFF3333;
    private const COLOR_GRAY   = 0x888888;

    function initialize(run as PhysicalRun) {
        View.initialize();
        _run = run;
    }

    function onShow() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        if (_run.tick()) {
            physicalVibe(400);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 24, Graphics.FONT_XTINY, physicalFit(dc, _run.name, Graphics.FONT_XTINY, 220),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 48, Graphics.FONT_XTINY, _run.attempts.size().toString() + " tentative(s)",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_run.phase == PHYS_IDLE) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_MEDIUM, "Prêt ?",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 160, Graphics.FONT_XTINY, "↑ Démarrer",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_RUNNING) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_NUMBER_MEDIUM, physicalClock(_run.elapsedInAttempt()),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 160, Graphics.FONT_XTINY, "↑ Arrêter",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_COUNTDOWN) {
            var left = _run.secondsLeft();
            dc.setColor(left <= 3 ? COLOR_RED : COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_NUMBER_MEDIUM, left.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_ENTERING_REPS) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 90, Graphics.FONT_XTINY, "Répétitions ?",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, 130, Graphics.FONT_NUMBER_MEDIUM, _run.repsInput.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 170, Graphics.FONT_XTINY, "↑/↓  ● Valider",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "↩ Terminer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class PhysicalRunDelegate extends WatchUi.BehaviorDelegate {
    private var _run as PhysicalRun;

    function initialize(run as PhysicalRun) {
        BehaviorDelegate.initialize();
        _run = run;
    }

    function onNextPage() as Boolean {
        _run.onUp();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _run.onDown();
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        _run.onConfirm();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        if (_run.hasAttempts()) {
            var dict = _run.toDictionary();
            Communications.transmit(dict, null, new TransmitListener(dict));
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
```

- [ ] **Step 4: Compile to verify**

```bash
cd garmin-app && "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" -d fr255 -f monkey.jungle -o "${TMPDIR:-/tmp}/physical-check.prg" -y developer_key -w
```
Expected: `BUILD SUCCESSFUL`, with only the pre-existing `_sync` unused-variable warning (Task 7 must already be committed, since `physicalSlot_<i>` is read here — it is, by plan order).

- [ ] **Step 5: Commit**

```bash
git add garmin-app/source/PhysicalMenu.mc garmin-app/source/PhysicalView.mc garmin-app/source/MainMenu.mc
git diff --cached --stat
git commit -m "feat(watch): add Physique menu, run view and MainMenu entry" -m "Compile-verified with monkeyc (BUILD SUCCESSFUL); not run on a real device." -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Final manual verification (by the user, after all tasks)

1. Rebuild and copy the watch `.prg` (Monkey C: Build for Device → `garmin-app/bin/garminapp.prg` → `GARMIN/APPS/`). This plan's watch code is compile-verified but has not run on a real device or the simulator.
2. iPhone: Accueil → **Physique** → create a custom chrono exercise (e.g. "200m") and a custom duration exercise (e.g. "30 sec squat jumps", 30s); confirm the built-in list shows 25m/50m/100m/Suicide/1 min aller-retour sprint.
3. iPhone: run the chrono exercise — démarrer, arrêter (attempt recorded), nouvelle tentative, terminer, enregistrer; check it lands in the physical history and **not** in Historique/Stats/Trophées.
4. iPhone: run the duration exercise — démarrer, let the countdown reach 0 (vibration/sound), enter a rep count, valider, do a second attempt, terminer, enregistrer.
5. iPhone: **Envoyer à la montre** → an emplacement for each exercise kind; the alert says the send succeeded.
6. Watch: main menu → **Physique** → both slots are listed with their mode → run the chrono one (HAUT starts/stops, multiple attempts, BACK ends and sends) and the duration one (HAUT starts the countdown, vibration at the end, HAUT/BAS adjust the rep count, SELECT confirms and restarts the countdown, BACK ends and sends). Confirm both sessions land on the iPhone with the ⌚ badge, each only once even after restarting the watch app.

---

## Self-Review Notes

- **Spec coverage:** models/kinds/library/limits (Task 1); store with 5-slot copies and `(date, exerciseName)` dedupe (Task 2); editor with kind locked after creation (Task 3); phone run view covering both kinds, multiple attempts, idle-timer disabled, quit confirm, summary/save (Task 4); `physicalSlot` send and `physicalSession` routing that leaves Dribble/shooting messages untouched (Task 5); Home entry, exercise list/edit/send-to-slot, separate history (Task 6); watch storage with Number-or-Long handling (Task 7); watch menu, MainMenu entry and run view with the chrono/countdown/reps state machine, vibration, completion transmit via the existing `PendingQueue` retry path (Task 8, built as one task because the menu's `onSelect` directly constructs the run view's classes — same reasoning as Dribble's combined menu+timer task); manual checklist for what cannot be automated. Out-of-scope items (editing a saved attempt, personal-best tracking, stats/trophy integration, watch-side exercise creation, changing an exercise's kind) have no task, on purpose.
- **Placeholder scan:** none; every step has literal code or a literal command. (The plan's self-scan flagged two false positives — Monkey C's `toDouble()` case-insensitively contains the substring "todo" — neither is a real placeholder.) pbxproj UUIDs `ADF`–`AEC` were pre-allocated, checked unused, and this plan's Task 1–6 Swift code plus Task 7–8 Monkey C code were drafted and **actually compiled together in this environment** (`xcodebuild` → `BUILD SUCCEEDED`; `monkeyc` → `BUILD SUCCESSFUL`) before being written into this plan, then reverted so execution starts from a clean tree — the code blocks above are the exact verified text.
- **Type consistency:** `PhysicalTimer.secondsRemaining/isFinished`, `PhysicalStore` members, `PhysicalExerciseEditorView(exercise:)`, `PhysicalRunView(exercise:)`, `sendPhysicalSlot(_:exercise:)`, and the watch message keys are named identically in every task that touches them. The ceiling-rounding rule for countdown remaining seconds is implemented identically on both platforms (`PhysicalTimer.secondsRemaining` in Swift, `PhysicalRun.secondsLeft` in Monkey C) and was verified against the same test values during drafting.
