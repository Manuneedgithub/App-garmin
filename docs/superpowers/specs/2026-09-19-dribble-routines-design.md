# Dribble Routines — Design Spec

**Date:** 2026-09-19
**Status:** Approved
**Scope:** A new training type, independent from shooting sessions: timed dribble routines built from ordered steps (a named drill for N seconds, or a rest for N seconds). Routines are created and edited on the iPhone, played on the iPhone (timer with sound/vibration alerts) or sent to one of 5 watch slots and played on the watch. Finished sessions land in a separate dribble history.

---

## Decisions

| Topic | Decision |
|---|---|
| Platforms | iPhone (editor, library, timer, history) **and** Garmin watch (timer only, routines pushed from the phone) |
| Architecture | Self-contained dribble module (`DribbleRoutine`, `DribbleSession`, `DribbleStore`). `WorkoutSession`, `SessionStore`, stats, calendar and trophies are **not touched** |
| History | Separate: dribble sessions never enter Historique/Stats/Trophées and carry no shot data |
| Step model | A step is either a drill (name + seconds) or a rest (seconds). Drills are referenced by **name (String)**, not ID, so the watch needs no lookup table and user-added drills sync for free |
| Drill library | Built-in list + free-text drills the user adds on the phone (stored locally) |
| Routine count | Unlimited on the phone; 5 watch slots (same idea as the existing shooting-workout slots), the user chooses what goes where |
| Timer features | Step-change alerts only: vibration everywhere, plus a beep on the phone, at each step change and on the last 3 seconds of a step. **No** pause, skip or start countdown |
| Timer accuracy (phone) | Driven by wall-clock time (`Date`), not by counting ticks, so a backgrounded/throttled app doesn't drift; screen kept awake during a routine |
| Stats/trophies | Out of scope. Dribble sessions don't feed streaks, calendar or trophies |

---

## Data model — new file `Models/Dribble.swift`

```swift
import Foundation

struct DribbleStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var drill: String?        // nil = rest
    var seconds: Int          // 5...600, step of 5

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
    var date: Date                    // start time; (date, routineName) dedupes watch re-sends
    var totalSeconds: Int             // work + rest actually elapsed
    var drillTimes: [DribbleDrillTime]
    var sentFromWatch: Bool
}

enum DribbleLibrary {
    static let builtInDrills = [
        "Cross", "Behind the back", "In and out", "Between the legs",
        "Crossover", "Hesitation", "Double cross", "Pound dribble",
    ]
    static let maxSteps = 20
}
```

Limits: at most `DribbleLibrary.maxSteps` (20) steps per routine, so the watch payload and menu stay small.

---

## Timer engine — new file `Models/DribbleTimerEngine.swift`

Pure, no UI or `Timer` dependency, testable with the same `swiftc` script approach as the trophy engine. Given a routine and the seconds elapsed since start it answers: which step is current, seconds left in it, whether the routine is finished, and which alert events fired between two elapsed values.

```swift
struct DribbleTimerState: Equatable {
    var stepIndex: Int
    var secondsLeftInStep: Int
    var isFinished: Bool
}

enum DribbleAlert: Equatable {
    case stepChanged(newIndex: Int)
    case countdown(secondsLeft: Int)   // 3, 2, 1
    case finished
}

enum DribbleTimerEngine {
    static func state(for steps: [DribbleStep], elapsed: Int) -> DribbleTimerState
    // Alerts to fire when going from `from` to `to` elapsed seconds (from < to).
    // Robust to skipped seconds (backgrounding): every crossed boundary is reported once.
    static func alerts(for steps: [DribbleStep], from: Int, to: Int) -> [DribbleAlert]
    // Per-drill seconds for a completed run (rests excluded).
    static func drillTimes(for steps: [DribbleStep]) -> [DribbleDrillTime]
}
```

Countdown alerts are only emitted for steps longer than 3 seconds, so a 5 s step doesn't beep continuously.

---

## `DribbleStore` — new file `Models/DribbleStore.swift`

Same conventions as `SessionStore`'s sub-stores: singleton, `@Published private(set)`, `UserDefaults` + `JSONEncoder`/`JSONDecoder`.

- `routines: [DribbleRoutine]` (key `basket_dribble_routines`), with `save(_:)` (insert or update by id) and `delete(_:)`.
- `customDrills: [String]` (key `basket_dribble_custom_drills`), with `addCustomDrill(_:)` (trimmed, non-empty, case-insensitive dedupe against built-ins and existing customs). `allDrills` = built-ins + customs.
- `watchSlots: [DribbleRoutine?]` (5 entries, key `basket_dribble_watch_slots`): a **copy** of the routine at send time, like the existing shooting slots, so editing the library doesn't silently change what the watch has.
- `sessions: [DribbleSession]` (key `basket_dribble_sessions`), with `add(_:)` that ignores an exact `(date, routineName)` duplicate — the same at-least-once re-send risk found and fixed for shooting sessions (watch may retransmit if its completion callback is lost).

---

## iPhone UI

- **Entry point:** a "Dribble" button on `HomeView`, next to "Entraînement complet", opening a `DribbleHomeView` sheet.
- **`DribbleHomeView`:** list of routines (name, step count, total time). Per routine: tap → start on phone, "Modifier", "Envoyer à la montre" (choose slot 1–5, reusing the send/alert pattern of `SlotsView`). Buttons for "Nouvelle routine" and "Historique dribble".
- **`DribbleRoutineEditorView`:** name field; ordered step list with drag-to-reorder and swipe-to-delete; "Ajouter un exercice" (picker over `allDrills`, with "Nouvel exercice…" to type a custom name) and "Ajouter un repos"; per-step `Stepper` for seconds (5–600, by 5); live total time.
- **`DribbleTimerView`:** big countdown, current step name (or "Repos"), next step preview, routine progress bar. Alerts: `UINotificationFeedbackGenerator` + a system sound at each step change, lighter haptic/sound on the last 3 seconds. `UIApplication.shared.isIdleTimerDisabled = true` while running, restored on exit. Elapsed time is `Date().timeIntervalSince(start)` sampled by a 0.25 s `Timer`; each tick feeds `DribbleTimerEngine.alerts(from: lastElapsed, to: elapsed)`. Ends on a summary (total time, time per drill) with "Enregistrer" and "Quitter"; quitting mid-routine asks for confirmation.
- **`DribbleHistoryView`:** sessions newest first (routine name, date, duration, ⌚ badge if from the watch), tap for time per drill.

All new views/files must be registered in `project.pbxproj` (this project does not pick up files from disk).

---

## Watch ⇄ phone

**Phone → watch (`GarminManager.sendDribbleSlot(_:routine:)`)** — same wake-then-send pattern as `sendSlot`/`sendCustomSpots`:

```swift
["type": "dribbleSlot", "index": i, "name": routine.name,
 "steps": routine.steps.map { ["drill": $0.drill ?? "", "seconds": $0.seconds] }]
```

An empty `drill` string means rest.

**Watch storage (`BasketApp.mc`, `onPhoneAppMessage`):** new `"dribbleSlot"` branch validating `index` 0–4 and each step (`seconds` accepted as `Number` **or** `Long`, the nested-integer pitfall found earlier), then `Application.Storage.setValue("dribbleSlot_<i>", {name, steps})`.

**Watch UI (new file `DribbleMenu.mc` + timer view):** a fourth item in `MainMenu.mc` ("Dribble") lists the 5 slots (name and total time, or "vide"). Selecting one starts a view driven by a 1 s `Timer.Timer`, computing state from `Time.now()` minus start (same wall-clock principle as the phone). It shows step name, seconds left, next step. `Attention.vibrate` at each step change and on the last 3 seconds. On completion it transmits the session and shows a short summary.

**Watch → phone:**

```
{"type": "dribbleSession", "routineName": ..., "startTime": <unix>, "totalSeconds": ...,
 "drillTimes": [{"drill": ..., "seconds": ...}, ...]}
```

Sent with the existing `Communications.transmit()` + `PendingQueue` retry path. **Required change on the phone:** `GarminManager.receivedMessage` currently hands every dictionary to `parseAndStore` (a shooting session). It must first check `dict["type"] == "dribbleSession"` and route to `DribbleStore.add` (`sentFromWatch = true`); shooting messages carry no `type` key and keep their current path unchanged.

**Verification limits:** no Monkey C compiler exists in this environment, so all `.mc` changes are checked by inspection and pattern-matching against existing code only, and need a real build/flash. The watch timer view and `Attention` usage are new API surface for this project and are the riskiest part.

---

## Testing

- `Scripts/dribble_engine_tests.swift`, compiled with `swiftc` against `Dribble.swift` + `DribbleTimerEngine.swift` (same approach as `trophy_logic_tests.swift`, using `precondition`, not `assert`): step boundaries, state at every step edge, the user's example routine, `alerts` across a big jump (backgrounding), countdown suppressed on short steps, `finished` fires exactly once, `drillTimes` excludes rests and sums repeated drills.
- iPhone UI and `DribbleStore` persistence: build verification plus a manual pass (nothing here has UI test coverage).
- Watch: manual pass on the real device after rebuilding and copying the `.prg`.

---

## Out of scope

- Pause/resume, skip step, start countdown (explicitly declined).
- Repeating a group of steps ("×3 rounds"): a routine is a flat list; the user can duplicate steps.
- Dribble stats, streak/calendar/trophy integration, sharing routines.
- Creating or editing routines on the watch.
