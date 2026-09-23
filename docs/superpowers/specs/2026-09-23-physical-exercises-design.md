# Physical Exercises — Design Spec

**Date:** 2026-09-23
**Status:** Approved
**Scope:** A new training type, independent from shooting sessions and from Dribble: single physical exercises (sprint distances, timed drills, interval counts) run one at a time, with multiple timed/counted attempts per session. Exercises are created and edited on the iPhone, run on the iPhone (stopwatch or fixed-duration countdown) or sent to one of 5 watch slots and run on the watch. Finished sessions land in a separate physical-exercises history.

---

## Decisions

| Topic | Decision |
|---|---|
| Platforms | iPhone (editor, library, run screen, history) **and** Garmin watch (run only, exercises pushed from the phone) — same split as Dribble |
| Architecture | Self-contained module (`PhysicalExercise`, `PhysicalSession`, `PhysicalStore`). `WorkoutSession`, `SessionStore`, `DribbleStore`, stats, calendar and trophies are **not touched** |
| History | Separate: physical sessions never enter Historique/Stats/Trophées/streak calendar and carry no shot or dribble data |
| Structure | No multi-step routines (unlike Dribble): a session is one exercise run one or more times in a row — each run is an **attempt** |
| Exercise kinds | Two kinds, fixed per exercise: **Chrono** (stopwatch — you time how long it takes: 25m, 100m, Suicide) and **Durée fixe** (fixed-duration countdown — you count repetitions done within it: "1 min aller-retour sprint") |
| Attempts | Multiple attempts per session, each recorded; the session ends when the user stops attempting and taps "Terminer" |
| Exercise library | Built-in list + free-text exercises the user adds on the phone (name + kind, and a fixed duration if kind is Durée fixe), stored locally |
| Exercise count | Unlimited on the phone; 5 watch slots (same idea as Dribble/shooting slots), the user chooses what goes where |
| Stats/trophies | Out of scope. Physical sessions don't feed streaks, calendar or trophies |
| Editing | No editing of a saved attempt's value after the fact; a session can only be deleted as a whole |

---

## Data model — new file `Models/Physical.swift`

```swift
import Foundation

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
        PhysicalExercise(name: "25m", kind: .chrono, fixedSeconds: nil),
        PhysicalExercise(name: "50m", kind: .chrono, fixedSeconds: nil),
        PhysicalExercise(name: "100m", kind: .chrono, fixedSeconds: nil),
        PhysicalExercise(name: "Suicide", kind: .chrono, fixedSeconds: nil),
        PhysicalExercise(name: "1 min aller-retour sprint", kind: .duration, fixedSeconds: 60),
    ]
    static let maxNameLength = 30
    static let fixedSecondsRange = 5...600
    static let maxRepsPerAttempt = 50
}
```

Each exercise's `kind` is fixed at creation (the editor does not let a Chrono exercise turn into a Durée fixe one later, or vice versa — delete and recreate instead). `fixedSeconds` is the single source of truth for a Durée fixe exercise's countdown length; Chrono exercises carry no duration.

---

## `PhysicalStore` — new file `Models/PhysicalStore.swift`

Same conventions as `DribbleStore`: singleton, `@Published private(set)`, `UserDefaults` + `JSONEncoder`/`JSONDecoder`.

- `exercises: [PhysicalExercise]` (key `basket_physical_exercises`), seeded with `PhysicalLibrary.builtIn` on first launch (no stored value yet). `save(_:)` (insert or update by id) and `delete(_:)` — a built-in exercise can be deleted like any other; nothing restores it automatically.
- `watchSlots: [PhysicalExercise?]` (5 entries, key `basket_physical_watch_slots`): a **copy** of the exercise at send time, exactly like Dribble's watch slots.
- `sessions: [PhysicalSession]` (key `basket_physical_sessions`), with `add(_:)` that ignores an exact `(date, exerciseName)` duplicate (same at-least-once re-send risk as Dribble/shooting).

---

## iPhone UI

- **Entry point:** a "Physique" button on `HomeView`, under the "Dribble" button, opening a `PhysicalHomeView` sheet.
- **`PhysicalHomeView`:** list of exercises (name, a "Chrono" or "Durée fixe" badge, and the fixed duration when applicable). Per exercise: tap → start on phone, "Modifier", "Envoyer à la montre" (choose slot 1–5), "Supprimer". Buttons for "Nouvel exo" and "Historique".
- **Add/edit exercise:** name field; a segmented Chrono/Durée fixe picker; when Durée fixe is selected, a `Stepper` for the fixed duration (5–600s, step 5, same range as Dribble steps).
- **`PhysicalRunView`:**
  - **Chrono mode:** a running stopwatch (`Date`-based elapsed time, same wall-clock principle as Dribble, 0.25s tick), "Arrêter" records the current elapsed time as an attempt and resets the display to 0:00.00, with "Nouvelle tentative" (restart the stopwatch) and "Terminer" (go to the attempts summary).
  - **Durée fixe mode:** a countdown from `fixedSeconds` to 0 (vibration/sound at the end, same as Dribble's step-end alert), then a "Combien de répétitions ?" screen with a `Stepper` (0...`PhysicalLibrary.maxRepsPerAttempt`) to confirm the attempt's rep count, then "Nouvelle tentative" (restart the countdown) or "Terminer".
  - Both modes keep the screen awake (`isIdleTimerDisabled`) while running, and show the list of attempts recorded so far during the session.
  - On "Terminer": a summary (all attempts) with "Enregistrer" (adds a `PhysicalSession` with `sentFromWatch: false`) and "Quitter" (discard, with confirmation if at least one attempt was recorded).
- **`PhysicalHistoryView`:** sessions newest first (exercise name, date, attempt count, ⌚ badge if from the watch), tap for the full list of attempts.

All new views/files must be registered in `project.pbxproj` (this project does not pick up files from disk).

---

## Watch ⇄ phone

**Phone → watch (`GarminManager.sendPhysicalSlot(_:exercise:)`)** — same wake-then-send pattern as `sendDribbleSlot`:

```swift
["type": "physicalSlot", "index": i, "name": exercise.name,
 "kind": exercise.kind.rawValue, "seconds": exercise.fixedSeconds as Any]
```

`seconds` is absent/null for a Chrono exercise.

**Watch storage (`BasketApp.mc`, `onPhoneAppMessage`):** new `"physicalSlot"` branch validating `index` 0–4, `name` (String), `kind` (String, "chrono" or "duration"), and `seconds` (Number or Long, required and ≥5 when `kind == "duration"`, ignored otherwise), then `Application.Storage.setValue("physicalSlot_<i>", {name, kind, seconds})`.

**Watch UI (new file `PhysicalMenu.mc` + run view):** a fifth item in `MainMenu.mc` ("Physique") lists the 5 slots (name + mode, or "vide"). Selecting one starts a view driven by a 1s `Timer.Timer`, computing elapsed/remaining time from `Time.now()` (same wall-clock principle as Dribble and as the phone):
- **Chrono slot:** UP starts/stops the stopwatch; each stop records an attempt and resets to 0; BACK ends the session and transmits.
- **Durée fixe slot:** UP starts the countdown; `Attention.vibrate` at 0; then UP/DOWN increment/decrement a rep counter (same idiom as `GoalDelegate.onNextPage`/`onPreviousPage`), SELECT confirms the attempt and restarts the countdown; BACK ends the session and transmits.

**Watch → phone:**

```
{"type": "physicalSession", "exerciseName": ..., "kind": "chrono"|"duration", "startTime": <unix>,
 "attempts": [{"seconds": ...} | {"reps": ...}, ...]}
```

Sent with the existing `Communications.transmit()` + `PendingQueue` retry path (the same `TransmitListener` Dribble reuses). **Required change on the phone:** `GarminManager.receivedMessage` already branches on `dict["type"]` (added for Dribble) — it gains one more case, `"physicalSession"`, routed to `PhysicalStore.add` (`sentFromWatch = true`); shooting messages (no `type` key) and Dribble messages are unaffected.

**Verification limits:** a Connect IQ SDK (`monkeyc`) and developer key are available on this machine (discovered during the Dribble feature work), so watch-side `.mc` changes can be compile-checked here, but not run on a real device/simulator. Compile verification plus careful inspection against the existing `DribbleView.mc`/`GoalView.mc` idioms replace a device test; the user must still do a real on-watch pass after rebuilding and copying the `.prg`.

---

## Testing

- No multi-step engine like Dribble's `DribbleTimerEngine`, so no dedicated `swiftc` test script is required for the core logic. If `PhysicalFormat` (time/rep formatting helpers) ends up non-trivial, a small `swiftc` script mirroring `dribble_engine_tests.swift` covers it; otherwise build verification plus a manual pass is sufficient (same bar as `DribbleStore`'s UI/persistence in the Dribble plan).
- iPhone UI and `PhysicalStore` persistence: build verification plus a manual pass.
- Watch: `monkeyc` compile verification plus inspection; manual pass on the real device after rebuilding and copying the `.prg`.

---

## Out of scope

- Editing a saved attempt's value, or reordering attempts within a session.
- Automatic personal-best tracking or ranking across sessions.
- Physical-exercise stats, streak/calendar/trophy integration, sharing exercises.
- Creating or editing exercises on the watch.
- Changing an exercise's kind after creation.
