# Shot Type + Court Map Feature — Design Spec

**Date:** 2026-06-06
**Status:** Approved
**Scope:** Add shot-type tracking (catch & shoot / off dribble / standing) to Garmin watch + iPhone, and add a court-map view showing per-spot stats with shot-type breakdown.

---

## Problem

The app tracks *where* you shoot from (9 exercise types / positions) but not *how* you shoot. A player's catch-and-shoot 3-pointer and their off-dribble pull-up from the same spot are fundamentally different skills that improve at different rates. Without this distinction the stats are too coarse to guide training.

---

## Decisions

| Topic | Decision |
|---|---|
| Shot types | 3 fixed types: Catch & Shoot, Avec dribble, À l'arrêt |
| Tracking source | Both Garmin (new menu level) and iPhone manual entry |
| Routines | Each series in a routine includes a shot type (mandatory) |
| Court view placement | 4th tab "Terrain" (Accueil · Historique · Stats · Terrain) |
| Court view purpose | Read-only stats — no workout launch from this view |
| Historical data | `shotType` is optional (`nil`) on old data; old sessions count toward spot totals but not per-type breakdowns |

---

## Data Model Changes

### New: `ShotType` enum — `Models.swift`

```swift
enum ShotType: Int, CaseIterable, Codable {
    case catchAndShoot = 0
    case offDribble    = 1
    case standing      = 2

    var name: String {
        switch self {
        case .catchAndShoot: return "Catch & Shoot"
        case .offDribble:    return "Avec dribble"
        case .standing:      return "À l'arrêt"
        }
    }
}
```

### Modified: `ShotSeries` — add optional `shotType`

```swift
struct ShotSeries: Codable, Identifiable {
    // … existing fields …
    var shotType: ShotType?   // nil = historical data, no type recorded
}
```

### Modified: `TemplateSeries` — shot type mandatory in routines

```swift
struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int
    var targetMade: Int?
    var shotType: ShotType       // required — routines always specify shot type
}
```

### New: `SpotStats` struct — `Models.swift`

```swift
struct SpotStats {
    let exerciseType: ExerciseType
    let totalShots: Int
    let totalMade: Int
    var percentage: Double { totalShots == 0 ? 0 : Double(totalMade) / Double(totalShots) * 100 }
    var byType: [ShotType: (shots: Int, made: Int)]   // only types with ≥1 shot
}
```

### Modified: `SessionStore` — new query method

```swift
func spotStats(for exerciseType: ExerciseType) -> SpotStats
```

Aggregates all `ShotSeries` (from both simple and complex sessions) matching the given exercise type. Historical series with `shotType == nil` contribute to `totalShots`/`totalMade` only, not to `byType`.

---

## Garmin Changes

### New file: `ShotTypeMenu.mc`

A `WatchUi.Menu2` with 3 items (Catch & Shoot, Avec dribble, À l'arrêt) and a delegate that stores the selected `shotTypeId: Number` then pushes `ShotCountMenu`.

```monkey-c
class ShotTypeMenuView extends WatchUi.Menu2 {
    function initialize(exerciseId as Number) {
        Menu2.initialize({:title => getExerciseName(exerciseId)});
        addItem(new WatchUi.MenuItem("Catch & Shoot", null, 0, null));
        addItem(new WatchUi.MenuItem("Avec dribble",  null, 1, null));
        addItem(new WatchUi.MenuItem("À l'arrêt",     null, 2, null));
    }
}

class ShotTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId as Number;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(exerciseId as Number, accumulator as SessionAccumulator or Null) { … }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var shotTypeId = item.getId() as Number;
        var menu = new ShotCountMenuView(_exerciseId, shotTypeId);
        var del  = new ShotCountMenuDelegate(_exerciseId, shotTypeId, _accumulator);
        WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
    }
}
```

### Modified: `ExerciseMenu.mc`

Both `ExerciseMenuDelegate` (free mode) and `ExerciseMenuGoalDelegate` (goal mode) currently push `ShotCountMenu` on selection. They will instead push `ShotTypeMenu`:

```monkey-c
// ExerciseMenuDelegate.onSelect (free mode)
var shotMenu = new ShotTypeMenuView(id);
var del      = new ShotTypeMenuDelegate(id, null);
WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);

// ExerciseMenuGoalDelegate.onSelect (goal mode)
var shotMenu = new ShotTypeMenuView(id);
var del      = new ShotTypeMenuDelegate(id, _accumulator);
WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);
```

### Modified: `ShotCountMenu.mc`

`ShotCountMenuView` and `ShotCountMenuDelegate` receive an additional `shotTypeId as Number` parameter. `ShotCountMenuDelegate` passes it to `WorkoutSession`.

### Modified: `WorkoutSession.mc`

Add `_shotType as Number` (default `-1` = not set). Include in `toDictionary()`:

```monkey-c
dict["shotTypeId"] = _shotType;
```

### Modified: `RoutineRunner.mc`

`RoutineRunner.initialize()` reads `shotTypeId` from each series dict. `currentShotTypeId()` accessor added. `RoutineStartDelegate.onSelect()` and `RoutineSeriesDoneDelegate.onSelect()` pass `shotTypeId` when creating `WorkoutSession`.

### Modified: `GarminManager.swift` — `sendRoutine(_:)`

Include `shotTypeId` in each series payload:

```swift
"series": template.series.map {
    [
        "exerciseId": $0.exerciseType.rawValue,
        "totalShots": $0.totalShots,
        "shotTypeId": $0.shotType.rawValue
    ]
}
```

---

## iPhone View Changes

### New: `CourtView.swift`

4th tab in `ContentView`. Contains:
- A SwiftUI `Canvas` or `Path`-based half-court (no external dependency)
- 9 tappable spots positioned to match the 9 `ExerciseType` positions
- Each spot colored by `SpotStats.percentage`: green ≥70%, orange 50–69%, red <50%, gray = no data
- Spot label shows the % (or "–" if no data)
- Tap → `NavigationLink` to `SpotDetailView`
- Filter picker at top: All sessions / Last 30 days / Last 7 days

### New: `SpotDetailView.swift`

Shows for one `ExerciseType`:
- Exercise name + total shots/made
- Global % with colored progress bar
- Section "Par type de tir" — for each `ShotType` with data: name, shots/made, %, mini progress bar
- Empty state if no sessions for this spot

### Modified: `ContentView.swift`

Add 4th tab:
```swift
CourtView()
    .tabItem { Label("Terrain", systemImage: "sportscourt") }
```

### Modified: `RoutineBuilderView.swift`

`SeriesRow` adds a shot type picker button (same pattern as the exercise picker — opens a sheet `ShotTypePickerSheet` with 3 choices). `TemplateSeries` already has `shotType: ShotType` after the model change.

### Modified: `ManualSessionView.swift`

Add a `Picker("Type de tir", selection: $shotType)` with `.segmented` style showing the 3 types. The selected value is stored in the new `ShotSeries.shotType` field.

---

## Data Flow

```
Garmin watch
  ShotTypeMenu (new) → ShotCountMenu → WorkoutView
  WorkoutSession.toDictionary() includes shotTypeId
  Communications.transmit() ──────────────────────────►
                                              GarminManager.handleSessionOrGuided()
                                              → WorkoutSession(fromGarmin:) reads shotTypeId
                                              → ShotSeries.shotType set
                                              → SessionStore.add()

iPhone (manual)
  ManualSessionView → ShotType picker → SessionStore.add()

iPhone (routine)
  RoutineBuilderView → TemplateSeries includes shotType
  GarminManager.sendRoutine() → payload includes shotTypeId per series
  Watch executes each series with correct shot type

Stats query
  CourtView → SessionStore.spotStats(for:) → SpotStats → colored spots
  SpotDetailView → SpotStats.byType → per-type bars
```

---

## Files Modified / Created

| File | Change |
|---|---|
| `ios-app/.../Models/Models.swift` | Add `ShotType`, `SpotStats`; modify `ShotSeries`, `TemplateSeries` |
| `ios-app/.../Models/SessionStore.swift` | Add `spotStats(for:)` |
| `ios-app/.../Views/CourtView.swift` | **New** — 4th tab court map |
| `ios-app/.../Views/SpotDetailView.swift` | **New** — spot detail with shot-type breakdown |
| `ios-app/.../Views/ContentView.swift` | Add 4th tab |
| `ios-app/.../Views/RoutineBuilderView.swift` | Add shot type picker in `SeriesRow` |
| `ios-app/.../Views/ManualSessionView.swift` | Add shot type picker |
| `ios-app/.../Managers/GarminManager.swift` | Include `shotTypeId` in `sendRoutine()` payload |
| `garmin-app/source/ShotTypeMenu.mc` | **New** — menu + delegate |
| `garmin-app/source/ExerciseMenu.mc` | Both delegates push `ShotTypeMenu` instead of `ShotCountMenu` |
| `garmin-app/source/ShotCountMenu.mc` | Accept `shotTypeId` param, pass to `WorkoutSession` |
| `garmin-app/source/WorkoutSession.mc` | Add `_shotType`, include in `toDictionary()` |
| `garmin-app/source/RoutineRunner.mc` | Read `shotTypeId` from series, pass to `WorkoutSession` |

---

## Error / Edge Cases

| Scenario | Behavior |
|---|---|
| Historical session (no `shotType`) | Contributes to spot total %, excluded from per-type breakdown |
| Spot with no sessions | Gray spot on court, "Aucune donnée" in detail view |
| `shotTypeId` missing from Garmin payload | Defaults to `nil` — treated as historical |
| Routine series missing `shotTypeId` | Watch falls back to `ShotType 0` (Catch & Shoot) — logged as warning |

---

## Out of Scope

- Launching a workout from the court view
- Filtering court map by shot type (show only C&S spots)
- Court map on Apple Watch / other wearables
- Adding new exercise types / positions
