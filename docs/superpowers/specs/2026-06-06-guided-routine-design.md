# Guided Routine Feature — Design Spec

**Date:** 2026-06-06  
**Status:** Approved  
**Scope:** Create workout routines on iPhone, send to Garmin FR255, execute autonomously

---

## Problem

The user wants to define a custom routine (e.g. "50 close shots, 20 lay-ups, 10 free throws") on the iPhone and launch it directly on the watch. The watch then executes each series in order, autonomously, without needing the phone during the workout.

---

## Constraints & Decisions

- **Exercise types:** Use the existing 9 types (freethrow, 3pts ×5, mid-distance ×3). No new types.
- **Shot count per series:** Free-form stepper, 1–100. (Not restricted to 5/10/15/20/25/30 chips.)
- **Series per routine:** Max 6 (Monkey C memory constraint).
- **Autonomy:** Once the watch receives the routine, it runs completely independently. The phone is not needed during the workout. Results are transmitted after each series via the existing `transmit()` + `PendingQueue` retry system.

---

## Architecture & Data Flow

```
iPhone                                   Garmin FR255
──────────────────────────────────────   ──────────────────────────────────
[TemplatesView] ──(tap "Guider")──►
GarminManager.sendRoutine(template)
  ├─ startGuidedSession(template)        onMessage({type:"routine", series:[...]})
  └─ sdk.sendMessage(payload, to: app) ─►  BasketApp stores _pendingRoutine
                                            ↓
                                         User selects "Objectif complexe"
                                            ↓
                                         RoutineStartView (series overview)
                                            ↓ START
                                         WorkoutView série 1
                                            ↓ (shots complete)
                                         RoutineSeriesDoneView
                                           transmit(série 1 result) ─────────►
                                                                        handleSessionOrGuided()
                                                                        guidedIndex: 0 → 1
                                            ↓ START
                                         WorkoutView série 2
                                            ... (repeat for each series)
                                         transmit(série N result) ───────────►
                                                                        guidedIndex == template.series.count
                                                                        → makeComplex() → store.add()
                                         RoutineFinalView (global summary)
                                            ↓ Terminer → pop to root
```

**Key protocol facts:**
- Each series result is transmitted individually using the existing `toDictionary()` + `Communications.transmit()` pathway.
- `PendingQueue` handles BT disconnections transparently (already in place).
- `GarminManager.handleSessionOrGuided()` already accumulates guided series when `guidedTemplate != nil`. No changes needed to that logic.
- The iPhone assembles the `ComplexWorkoutSession` automatically when `guidedIndex == template.series.count`.

---

## iPhone Changes

### 1. `RoutineBuilderView.swift` (new file)

Accessible via a `+` button in the `TemplatesView` header.

**UI:**
- `TextField` for routine name (e.g. "Matin court")
- `List` of series rows, each with:
  - Exercise picker (sheet presenting `ExerciseType.allCases`)
  - Shot count stepper, range 1–100, default 10
- "+" button to add a series (disabled when count == 6)
- Swipe-to-delete to remove a series
- "Sauvegarder" button → `store.saveTemplate(template)` → dismiss

**Models used:** `ComplexTemplate`, `TemplateSeries` — already exist, no changes.

**Validation:** At least 1 series required to enable Save.

### 2. `GarminManager.swift` — `sendRoutine(_:)`

New method:

```swift
func sendRoutine(_ template: ComplexTemplate) {
    guard let device = connectedDevice else { return }
    let app = IQApp(uuid: appUUID, store: appUUID, device: device)
    let payload: [String: Any] = [
        "type": "routine",
        "series": template.series.map {
            ["exerciseId": $0.exerciseType.rawValue, "totalShots": $0.totalShots]
        }
    ]
    sdk.sendMessage(payload, to: app, progress: nil) { _ in }
    startGuidedSession(template)
}
```

### 3. `TemplatesView.swift` — wire "Guider la montre" button

Change `TemplateCard`'s `onLaunchGuided` to call `garmin.sendRoutine(template)` instead of `garmin.startGuidedSession(template)`.

---

## Garmin Changes

### 1. `BasketApp.mc` — message reception

Add to the `BasketApp` class:

- `private var _pendingRoutine as Dictionary or Null` (initialized `null` in `initialize()`)
- Override `onMessage(message as Object) as Void`:
  - Cast to `Dictionary`; if cast fails, return
  - If `message["type"] == "routine"` → store in `_pendingRoutine`
  - Otherwise → ignore (SyncManager uses `Communications.transmit` callbacks, not `onMessage`; no delegation needed)
- `function getPendingRoutine() as Dictionary or Null` — returns `_pendingRoutine`
- `function clearPendingRoutine() as Void` — sets `_pendingRoutine = null`

### 2. `MainMenu.mc` — wire "Objectif complexe" branch

Replace the empty `id == 2` branch with:

```monkey-c
} else if (id == 2) {
    var routine = getApp().getPendingRoutine();
    if (routine == null) {
        var view = new RoutineWaitView();
        var del  = new RoutineWaitDelegate();
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    } else {
        getApp().clearPendingRoutine();
        var runner = new RoutineRunner(routine);
        var view   = new RoutineStartView(runner);
        var del    = new RoutineStartDelegate(runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }
}
```

### 3. `RoutineRunner.mc` (new file)

#### `RoutineRunner` class

```
private var _plannedSeries as Array   // [{exerciseId, totalShots}]
private var _currentIndex  as Number  // starts at 0
private var _accumulator   as SessionAccumulator
```

Methods:
- `initialize(routine as Dictionary)` — parses `routine["series"]` into `_plannedSeries`, creates `SessionAccumulator`
- `currentSeries() as Dictionary` — returns `_plannedSeries[_currentIndex]`
- `isLastSeries() as Boolean` — `_currentIndex == _plannedSeries.size() - 1`
- `totalSeries() as Number`
- `seriesNumber() as Number` — 1-based display index (`_currentIndex + 1`)
- `onSeriesComplete(session as WorkoutSession) as Void`:
  - `_accumulator.addSeries(session)`
  - `Communications.transmit(session.toDictionary(), null, new TransmitListener(session.toDictionary()))`
  - `_currentIndex++`

#### `RoutineWaitView` / `RoutineWaitDelegate`

Simple centered message: "Ouvre l'app iPhone et appuie sur 'Guider la montre'". BACK → pop.

#### `RoutineStartView` / `RoutineStartDelegate`

Displays:
- "Routine guidée" (gray, xtiny)
- "N séries · X tirs" (white, tiny)
- Compact list of exercises: each on one line as "• [Exercice] × N" (up to 6 lines)
- "▶ START = commencer" (orange)

START → calls `runner.startNextSeries()` which creates `WorkoutSession` + pushes `WorkoutView` with `RoutineWorkoutDelegate`.

#### `RoutineSeriesDoneView` / `RoutineSeriesDoneDelegate`

Displayed after each completed series (replaces `SummaryView` in the routine flow).

Displays:
- "Série X / N terminée" (gray)
- Exercise name (white)
- Score "made / total" (large)
- Percentage (colored)
- If more series: "→ Prochaine : [Exercice] × N tirs" (orange)
- If last series: "Dernière série !" (green)
- "▶ START = continuer" / "↩ Abandonner"

START:
- If more series: `runner.startNextSeries()` → pushes next `WorkoutView`
- If last: pushes `RoutineFinalView`

BACK → `RoutineFinalView` (partial results — series already transmitted).

#### `RoutineFinalView` / `RoutineFinalDelegate`

Displays global summary using `runner.accumulator`:
- "Séance terminée" + "N séries"
- Total score + percentage
- Elapsed time
- "▶ Terminer" → pop to root (no re-send — individual series already transmitted)

#### `WorkoutDelegate` modification

Pass an optional `RoutineRunner or Null` to `WorkoutDelegate` (new parameter, default `null`). After all shots are done:
- If `_runner == null`: existing behavior (push `SummaryView`)
- If `_runner != null`: call `_runner.onSeriesComplete(session)` then push `RoutineSeriesDoneView`

No new delegate class needed.

---

## Files Modified / Created

| File | Change |
|------|--------|
| `ios-app/.../Views/RoutineBuilderView.swift` | **New** — template creation UI |
| `ios-app/.../Managers/GarminManager.swift` | Add `sendRoutine(_:)` |
| `ios-app/.../Views/TemplatesView.swift` | Wire "Guider" button to `sendRoutine` |
| `garmin-app/source/BasketApp.mc` | Add `_pendingRoutine`, `onMessage`, accessors |
| `garmin-app/source/MainMenu.mc` | Implement `id == 2` branch |
| `garmin-app/source/RoutineRunner.mc` | **New** — all routine Garmin logic |
| `garmin-app/source/WorkoutView.mc` | Add optional `RoutineRunner or Null` param to `WorkoutDelegate`, branch post-series nav |

---

## Error Cases

| Scenario | Behavior |
|----------|----------|
| "Guider la montre" tapped, watch not connected | `sendRoutine` exits early (guard `connectedDevice`). User sees no feedback — consider a toast in a future iteration. |
| "Objectif complexe" selected, no routine pending | `RoutineWaitView` shown: "Ouvre l'app iPhone…" |
| BT drops mid-workout | Each series already sent → `PendingQueue` retries on reconnect. Workout continues normally on watch. |
| User abandons mid-routine (BACK) | Partial results already transmitted. iPhone's `guidedIndex` will be < `template.series.count` → guided session stays open until next routine or `cancelGuidedSession()`. Future: add a "cancel guided" signal. |

---

## Out of Scope

- New exercise types (lay-up, close shot) — can be added independently later
- Reordering series by drag in `RoutineBuilderView` — tap delete + re-add is sufficient for v1
- Toast/feedback when "Guider" is tapped with watch disconnected
- Cancelling an in-progress guided session from the iPhone mid-workout
