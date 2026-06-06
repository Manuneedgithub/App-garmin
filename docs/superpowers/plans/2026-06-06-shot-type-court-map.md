# Shot Type + Court Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shot-type tracking (Catch & Shoot / Avec dribble / À l'arrêt) to Garmin watch and iPhone, and add a "Terrain" tab showing per-spot stats with shot-type breakdown.

**Architecture:** A new `ShotType` enum propagates from the Garmin (new ShotTypeMenu inserted between exercise and shot-count menus) through `toDictionary()` / `fromGarmin:` to iOS models, then aggregated into `SpotStats` by `SessionStore.spotStats(for:)` and displayed in a SwiftUI Canvas-based court map.

**Tech Stack:** Monkey C (Connect IQ SDK 9.1.0), Swift 5 / SwiftUI (iOS 16+), SwiftUI Canvas, UserDefaults/JSONEncoder, No external dependencies.

---

## File Map

| File | Action |
|---|---|
| `ios-app/BasketTrainer/Models/Models.swift` | Modify — add `ShotType`, `SpotStats`, extend `ShotSeries`, `TemplateSeries`, `WorkoutSession` |
| `ios-app/BasketTrainer/Models/SessionStore.swift` | Modify — add `spotStats(for:)` |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Modify — include `shotTypeId` in `sendRoutine()` |
| `ios-app/BasketTrainer/Views/RoutineBuilderView.swift` | Modify — add shot type picker in `SeriesRow` |
| `ios-app/BasketTrainer/Views/ManualSessionView.swift` | Modify — add shot type picker in simple + complex forms |
| `ios-app/BasketTrainer/Views/CourtView.swift` | Create — Canvas half-court + 9 tappable spots |
| `ios-app/BasketTrainer/Views/SpotDetailView.swift` | Create — per-spot stats with shot-type breakdown |
| `ios-app/BasketTrainer/Views/ContentView.swift` | Modify — add 4th tab |
| `ios-app/BasketTrainer.xcodeproj/project.pbxproj` | Modify — register 2 new Swift files |
| `garmin-app/source/WorkoutSession.mc` | Modify — add `_shotType`, update constructor + `toDictionary()` |
| `garmin-app/source/GoalSession.mc` | Modify — add `_shotType`, update constructor + `toDictionary()` |
| `garmin-app/source/ShotTypeMenu.mc` | Create — `ShotTypeMenuView` + `ShotTypeMenuDelegate` |
| `garmin-app/source/ExerciseMenu.mc` | Modify — both delegates push ShotTypeMenu instead of ShotCountMenu/GoalMenu |
| `garmin-app/source/ShotCountMenu.mc` | Modify — `ShotCountMenuDelegate` accepts `shotTypeId`, passes to `WorkoutSession` |
| `garmin-app/source/GoalMenu.mc` | Modify — `GoalMenuDelegate` accepts `shotTypeId`, passes to `GoalSession` |
| `garmin-app/source/GoalSummaryView.mc` | Modify — increase pop count from 3 to 4 |
| `garmin-app/source/RoutineRunner.mc` | Modify — add `currentShotTypeId()`, pass to `WorkoutSession` |

---

## Task 1: iOS Data Model

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift`
- Modify: `ios-app/BasketTrainer/Models/SessionStore.swift`

### Context

`ShotSeries` and `WorkoutSession` are the two places shot data lives on iOS. `TemplateSeries` drives routine templates. All three need `shotType`. Existing stored data has no `shotType` key — custom `init(from decoder:)` with `decodeIfPresent` prevents crashes on decode.

- [ ] **Step 1: Add `ShotType` enum to `Models.swift`** — insert after the closing `}` of `ExerciseType`:

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

- [ ] **Step 2: Add `shotType: ShotType?` to `ShotSeries`** — add after `var targetMade: Int?`:

```swift
var shotType: ShotType?   // nil = données historiques sans type
```

Update `ShotSeries.init(fromGarmin:)` to read `shotTypeId`:

```swift
init(fromGarmin data: [String: Any]) {
    let exId = data["exerciseId"] as? Int ?? 0
    self.exerciseType = ExerciseType(rawValue: exId) ?? .freethrow
    self.totalShots   = data["totalShots"] as? Int ?? 0
    self.madeShots    = data["madeShots"]  as? Int ?? 0
    self.results      = (data["results"] as? [Bool]) ?? []
    self.targetMade   = data["targetMade"] as? Int
    if let stId = data["shotTypeId"] as? Int {
        self.shotType = ShotType(rawValue: stId)
    } else {
        self.shotType = nil
    }
}
```

Add custom `CodingKeys` and `init(from decoder:)` to `ShotSeries` so old data decodes without `shotType`:

```swift
private enum CodingKeys: String, CodingKey {
    case id, exerciseType, totalShots, madeShots, results, targetMade, shotType
}

init(from decoder: Decoder) throws {
    let c    = try decoder.container(keyedBy: CodingKeys.self)
    id           = try c.decodeIfPresent(UUID.self,         forKey: .id) ?? UUID()
    exerciseType = try c.decode(ExerciseType.self,          forKey: .exerciseType)
    totalShots   = try c.decode(Int.self,                   forKey: .totalShots)
    madeShots    = try c.decode(Int.self,                   forKey: .madeShots)
    results      = try c.decodeIfPresent([Bool].self,       forKey: .results) ?? []
    targetMade   = try c.decodeIfPresent(Int.self,          forKey: .targetMade)
    shotType     = try c.decodeIfPresent(ShotType.self,     forKey: .shotType)
}
```

- [ ] **Step 3: Extend `TemplateSeries`** — add `shotType` with default and custom decoder:

```swift
struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int
    var targetMade: Int?
    var shotType: ShotType = .catchAndShoot

    private enum CodingKeys: String, CodingKey {
        case exerciseType, totalShots, targetMade, shotType
    }

    init(exerciseType: ExerciseType, totalShots: Int,
         targetMade: Int? = nil, shotType: ShotType = .catchAndShoot) {
        self.exerciseType = exerciseType
        self.totalShots   = totalShots
        self.targetMade   = targetMade
        self.shotType     = shotType
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        exerciseType = try c.decode(ExerciseType.self,      forKey: .exerciseType)
        totalShots   = try c.decode(Int.self,               forKey: .totalShots)
        targetMade   = try c.decodeIfPresent(Int.self,      forKey: .targetMade)
        shotType     = try c.decodeIfPresent(ShotType.self, forKey: .shotType) ?? .catchAndShoot
    }
}
```

- [ ] **Step 4: Add `shotType: ShotType?` to `WorkoutSession`** — add after `var duration: TimeInterval?`:

```swift
var shotType: ShotType?   // for simple sessions (no series array)
```

Update `WorkoutSession.init(fromGarmin:)` to read `shotTypeId`:

```swift
if let stId = data["shotTypeId"] as? Int {
    shotType = ShotType(rawValue: stId)
} else {
    shotType = nil
}
```

Add `shotType` to the Codable keys in `WorkoutSession` — since `WorkoutSession` is a `struct` with `Codable`, add custom decoder (after the existing `init` methods, before the closing `}`):

```swift
private enum CodingKeys: String, CodingKey {
    case id, exerciseType, totalShots, madeShots, results, date,
         sentFromWatch, series, duration, shotType
}

init(from decoder: Decoder) throws {
    let c       = try decoder.container(keyedBy: CodingKeys.self)
    id           = try c.decodeIfPresent(UUID.self,              forKey: .id) ?? UUID()
    exerciseType = try c.decode(ExerciseType.self,               forKey: .exerciseType)
    totalShots   = try c.decode(Int.self,                        forKey: .totalShots)
    madeShots    = try c.decode(Int.self,                        forKey: .madeShots)
    results      = try c.decodeIfPresent([Bool].self,            forKey: .results) ?? []
    date         = try c.decodeIfPresent(Date.self,              forKey: .date) ?? Date()
    sentFromWatch = try c.decodeIfPresent(Bool.self,             forKey: .sentFromWatch) ?? false
    series       = try c.decodeIfPresent([ShotSeries].self,      forKey: .series)
    duration     = try c.decodeIfPresent(TimeInterval.self,      forKey: .duration)
    shotType     = try c.decodeIfPresent(ShotType.self,          forKey: .shotType)
}
```

- [ ] **Step 5: Add `SpotStats` struct to `Models.swift`** — add after `ExerciseStats`:

```swift
struct SpotStats {
    let exerciseType: ExerciseType
    let totalShots: Int
    let totalMade: Int
    var percentage: Double {
        totalShots == 0 ? 0 : Double(totalMade) / Double(totalShots) * 100
    }
    var byType: [ShotType: (shots: Int, made: Int)]
}
```

- [ ] **Step 6: Add `spotStats(for:)` to `SessionStore.swift`** — add after `func stats(for:)`:

```swift
func spotStats(for exerciseType: ExerciseType) -> SpotStats {
    var totalShots = 0
    var totalMade  = 0
    var byType: [ShotType: (shots: Int, made: Int)] = [:]

    for session in sessions {
        if let seriesList = session.series {
            for s in seriesList where s.exerciseType == exerciseType {
                totalShots += s.totalShots
                totalMade  += s.madeShots
                if let t = s.shotType {
                    var e = byType[t] ?? (shots: 0, made: 0)
                    e.shots += s.totalShots
                    e.made  += s.madeShots
                    byType[t] = e
                }
            }
        } else if session.exerciseType == exerciseType {
            totalShots += session.totalShots
            totalMade  += session.madeShots
            if let t = session.shotType {
                var e = byType[t] ?? (shots: 0, made: 0)
                e.shots += session.totalShots
                e.made  += session.madeShots
                byType[t] = e
            }
        }
    }

    return SpotStats(exerciseType: exerciseType,
                     totalShots: totalShots,
                     totalMade: totalMade,
                     byType: byType)
}
```

- [ ] **Step 7: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift \
        ios-app/BasketTrainer/Models/SessionStore.swift
git commit -m "feat(ios): add ShotType, SpotStats, extend ShotSeries/WorkoutSession/TemplateSeries"
```

---

## Task 2: Garmin — WorkoutSession.mc + GoalSession.mc

**Files:**
- Modify: `garmin-app/source/WorkoutSession.mc`
- Modify: `garmin-app/source/GoalSession.mc`

### Context

`WorkoutSession` is used for free/multi mode; `GoalSession` for goal mode. Both need a `_shotType` field (stored as `Number`, default `-1` = not set) and must include `"shotTypeId"` in `toDictionary()`. All callers of `new WorkoutSession()` will be updated in Task 3 and Task 4.

- [ ] **Step 1: Extend `WorkoutSession.mc`**

In `WorkoutSession`, add field after `var startTime`:
```
var shotType as Number;  // -1 = not set
```

Change `initialize` signature to:
```monkey-c
function initialize(exId as Number, total as Number, shotTypeId as Number) {
    exerciseId   = exId;
    exerciseName = getExerciseName(exId);
    totalShots   = total;
    currentShot  = 0;
    madeShots    = 0;
    results      = new [0];
    startTime    = Time.now().value();
    shotType     = shotTypeId;
}
```

In `toDictionary()`, add `"shotTypeId" => shotType` to the returned dictionary:
```monkey-c
function toDictionary() as Dictionary {
    return {
        "exerciseId"   => exerciseId,
        "exerciseName" => exerciseName,
        "totalShots"   => totalShots,
        "madeShots"    => madeShots,
        "percentage"   => percentage(),
        "startTime"    => startTime,
        "results"      => results,
        "duration"     => Time.now().value() - startTime,
        "shotTypeId"   => shotType
    };
}
```

- [ ] **Step 2: Extend `GoalSession.mc`** — same pattern:

Add field after `var startTime`:
```
var shotType as Number;
```

Change `initialize` to:
```monkey-c
function initialize(exId as Number, target as Number, shotTypeId as Number) {
    exerciseId   = exId;
    exerciseName = getExerciseName(exId);
    targetMade   = target;
    madeShots    = 0;
    totalShots   = 0;
    results      = new [0];
    startTime    = Time.now().value();
    shotType     = shotTypeId;
}
```

In `toDictionary()`, add `"shotTypeId" => shotType`.

- [ ] **Step 3: Commit**

```bash
git add garmin-app/source/WorkoutSession.mc garmin-app/source/GoalSession.mc
git commit -m "feat(garmin): add shotType field to WorkoutSession and GoalSession"
```

---

## Task 3: Garmin — ShotTypeMenu + Wire All Menus

**Files:**
- Create: `garmin-app/source/ShotTypeMenu.mc`
- Modify: `garmin-app/source/ExerciseMenu.mc`
- Modify: `garmin-app/source/ShotCountMenu.mc`
- Modify: `garmin-app/source/GoalMenu.mc`
- Modify: `garmin-app/source/GoalSummaryView.mc`

### Context

`ShotTypeMenuDelegate` uses `_mode as Number` (0 = free/multi, 1 = goal) to decide which menu comes next. `ShotCountMenu` passes `shotTypeId` to `WorkoutSession`. `GoalMenu` passes it to `GoalSession`. `GoalSummaryDelegate` needs 4 pops (was 3) because ShotTypeMenu is now on the stack.

`ExerciseMenuDelegate` → mode 0 (free); `ExerciseMenuGoalDelegate` → mode 1 (goal).

- [ ] **Step 1: Create `garmin-app/source/ShotTypeMenu.mc`**

```monkey-c
import Toybox.WatchUi;
import Toybox.Lang;

class ShotTypeMenuView extends WatchUi.Menu2 {
    function initialize(exerciseId as Number) {
        Menu2.initialize({:title => getExerciseName(exerciseId)});
        addItem(new WatchUi.MenuItem("Catch & Shoot", null, 0, null));
        addItem(new WatchUi.MenuItem("Avec dribble",  null, 1, null));
        addItem(new WatchUi.MenuItem("À l'arrêt", null, 2, null));
    }
}

// _mode 0 = free/multi → ShotCountMenu
// _mode 1 = goal       → GoalMenu
class ShotTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId  as Number;
    private var _mode        as Number;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(exerciseId  as Number,
                        mode        as Number,
                        accumulator as SessionAccumulator or Null) {
        Menu2InputDelegate.initialize();
        _exerciseId  = exerciseId;
        _mode        = mode;
        _accumulator = accumulator;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var shotTypeId = item.getId() as Number;
        if (_mode == 1) {
            var view = new GoalMenuView(_exerciseId, 10);
            var del  = new GoalMenuDelegate(view, _exerciseId, shotTypeId);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        } else {
            var menu = new ShotCountMenuView(_exerciseId);
            var del  = new ShotCountMenuDelegate(_exerciseId, shotTypeId, _accumulator);
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

- [ ] **Step 2: Update `ExerciseMenu.mc`** — replace both delegate `onSelect` bodies:

`ExerciseMenuDelegate.onSelect`:
```monkey-c
function onSelect(item as WatchUi.MenuItem) as Void {
    var exerciseId = item.getId() as Number;
    var shotMenu   = new ShotTypeMenuView(exerciseId);
    var del        = new ShotTypeMenuDelegate(exerciseId, 0, _accumulator);
    WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);
}
```

`ExerciseMenuGoalDelegate.onSelect`:
```monkey-c
function onSelect(item as WatchUi.MenuItem) as Void {
    var exerciseId = item.getId() as Number;
    var shotMenu   = new ShotTypeMenuView(exerciseId);
    var del        = new ShotTypeMenuDelegate(exerciseId, 1, null);
    WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);
}
```

- [ ] **Step 3: Update `ShotCountMenu.mc`** — add `shotTypeId` param to delegate:

`ShotCountMenuDelegate`:
```monkey-c
class ShotCountMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId  as Number;
    private var _shotTypeId  as Number;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(exerciseId  as Number,
                        shotTypeId  as Number,
                        accumulator as SessionAccumulator or Null) {
        Menu2InputDelegate.initialize();
        _exerciseId  = exerciseId;
        _shotTypeId  = shotTypeId;
        _accumulator = accumulator;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var totalShots = item.getId() as Number;
        var session    = new WorkoutSession(_exerciseId, totalShots, _shotTypeId);
        var view       = new WorkoutView(session, _accumulator);
        var delegate   = new WorkoutDelegate(session, view, _accumulator, null);
        WatchUi.pushView(view, delegate, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

(`ShotCountMenuView` signature is unchanged — it only needs `exerciseId` for its title.)

- [ ] **Step 4: Update `GoalMenu.mc`** — add `shotTypeId` to `GoalMenuDelegate`:

```monkey-c
class GoalMenuDelegate extends WatchUi.BehaviorDelegate {
    private var _view       as GoalMenuView;
    private var _exerciseId as Number;
    private var _shotTypeId as Number;

    function initialize(view as GoalMenuView, exerciseId as Number, shotTypeId as Number) {
        BehaviorDelegate.initialize();
        _view       = view;
        _exerciseId = exerciseId;
        _shotTypeId = shotTypeId;
    }

    function onNextPage() as Boolean {
        var t = _view.getTarget() + 1;
        if (t > 50) { t = 50; }
        _view.setTarget(t);
        return true;
    }

    function onPreviousPage() as Boolean {
        var t = _view.getTarget() - 1;
        if (t < 1) { t = 1; }
        _view.setTarget(t);
        return true;
    }

    function onSelect() as Boolean {
        var session = new GoalSession(_exerciseId, _view.getTarget(), _shotTypeId);
        var view    = new GoalView(session);
        var del     = new GoalDelegate(session, view);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
```

- [ ] **Step 5: Update `GoalSummaryView.mc`** — change pop count from 3 to 4 in both `onSelect` and `onBack` of `GoalSummaryDelegate` (ShotTypeMenu is now on the stack):

```monkey-c
function onSelect() as Boolean {
    var dict = _session.toDictionary();
    Communications.transmit(dict, null, new GoalTransmitListener(dict));
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
}

function onBack() as Boolean {
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
}
```

- [ ] **Step 6: Commit**

```bash
git add garmin-app/source/ShotTypeMenu.mc \
        garmin-app/source/ExerciseMenu.mc \
        garmin-app/source/ShotCountMenu.mc \
        garmin-app/source/GoalMenu.mc \
        garmin-app/source/GoalSummaryView.mc
git commit -m "feat(garmin): insert ShotTypeMenu between exercise and count/goal menus"
```

---

## Task 4: Garmin — RoutineRunner.mc shot type support

**Files:**
- Modify: `garmin-app/source/RoutineRunner.mc`

### Context

`RoutineRunner` parses the series dict sent from iPhone. Each dict now contains `shotTypeId`. `currentShotTypeId()` and `shotTypeIdAt(i)` are new accessors. `RoutineStartDelegate.onSelect()` and `RoutineSeriesDoneDelegate.onSelect()` already call `new WorkoutSession(...)` — they need to pass the shot type.

- [ ] **Step 1: Add `currentShotTypeId()` and `shotTypeIdAt(i)` to `RoutineRunner`**

After `totalShotsAt(i)` add:
```monkey-c
function currentShotTypeId() as Number {
    var d = _series[_index] as Dictionary;
    if (d.hasKey("shotTypeId")) { return d["shotTypeId"] as Number; }
    return 0;  // fallback: Catch & Shoot
}

function shotTypeIdAt(i as Number) as Number {
    var d = _series[i] as Dictionary;
    if (d.hasKey("shotTypeId")) { return d["shotTypeId"] as Number; }
    return 0;
}
```

- [ ] **Step 2: Update `RoutineStartDelegate.onSelect()`** — pass `currentShotTypeId()`:

```monkey-c
function onSelect() as Boolean {
    var sess = new WorkoutSession(_runner.currentExerciseId(),
                                  _runner.currentTotalShots(),
                                  _runner.currentShotTypeId());
    var view = new WorkoutView(sess, null);
    var del  = new WorkoutDelegate(sess, view, null, _runner);
    WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    return true;
}
```

- [ ] **Step 3: Update `RoutineSeriesDoneDelegate.onSelect()`** — pass `currentShotTypeId()`:

```monkey-c
function onSelect() as Boolean {
    if (_runner.isComplete()) {
        var view = new RoutineFinalView(_runner);
        var del  = new RoutineFinalDelegate(_runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    } else {
        var sess = new WorkoutSession(_runner.currentExerciseId(),
                                      _runner.currentTotalShots(),
                                      _runner.currentShotTypeId());
        var view = new WorkoutView(sess, null);
        var del  = new WorkoutDelegate(sess, view, null, _runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }
    return true;
}
```

- [ ] **Step 4: Commit**

```bash
git add garmin-app/source/RoutineRunner.mc
git commit -m "feat(garmin): pass shotTypeId from RoutineRunner to WorkoutSession"
```

---

## Task 5: iOS — GarminManager + RoutineBuilderView + ManualSessionView

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`
- Modify: `ios-app/BasketTrainer/Views/RoutineBuilderView.swift`
- Modify: `ios-app/BasketTrainer/Views/ManualSessionView.swift`

### Context

`sendRoutine()` must include `shotTypeId` in each series dict. `RoutineBuilderView.SeriesRow` needs a shot type picker (matching the exercise picker pattern — a button that opens a sheet). `ManualSessionView` needs a shot type picker in both simple mode (sets `WorkoutSession.shotType`) and complex mode (sets `ShotSeries.shotType` in `SeriesEditorRow`).

- [ ] **Step 1: Update `GarminManager.swift` `sendRoutine()`**

Replace the `"series"` map:
```swift
"series": template.series.map {
    [
        "exerciseId": $0.exerciseType.rawValue,
        "totalShots": $0.totalShots,
        "shotTypeId": $0.shotType.rawValue
    ]
}
```

- [ ] **Step 2: Update `RoutineBuilderView.swift`** — add shot type picker to `SeriesRow`

In `SeriesRow`, add `@State private var showShotTypePicker = false`.

Add a shot type picker button below the exercise picker button in the `HStack`:
```swift
Button {
    showShotTypePicker = true
} label: {
    Label(series.shotType.name, systemImage: "figure.basketball")
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange)
        .clipShape(Capsule())
}
.sheet(isPresented: $showShotTypePicker) {
    ShotTypePickerSheet(selected: $series.shotType)
}
```

Add `ShotTypePickerSheet` at the bottom of `RoutineBuilderView.swift`:
```swift
struct ShotTypePickerSheet: View {
    @Binding var selected: ShotType
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(ShotType.allCases, id: \.self) { t in
                Button {
                    selected = t
                    dismiss()
                } label: {
                    HStack {
                        Text(t.name).foregroundStyle(.primary)
                        Spacer()
                        if selected == t {
                            Image(systemName: "checkmark").foregroundStyle(Color.orange)
                        }
                    }
                }
            }
            .navigationTitle("Type de tir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(Color.orange)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 3: Update `ManualSessionView.swift` — simple mode shot type picker**

Add `@State private var shotType: ShotType = .catchAndShoot` near the other simple-mode `@State` vars.

Add to `simpleForm`, after the "Tirs réussis" section:
```swift
VStack(alignment: .leading, spacing: 14) {
    SectionLabel(title: "Type de tir", icon: "figure.basketball")
    Picker("Type de tir", selection: $shotType) {
        ForEach(ShotType.allCases, id: \.self) { t in
            Text(t.name).tag(t)
        }
    }
    .pickerStyle(.segmented)
    .padding(16)
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14))
}
```

In `save()`, set `shotType` on simple sessions:
```swift
if mode == .simple {
    var s = WorkoutSession(exerciseType: exercise, totalShots: totalShots, madeShots: madeShots)
    s.date     = date
    s.shotType = shotType   // ← add this line
    store.add(s)
}
```

- [ ] **Step 4: Update `SeriesEditorRow` in `ManualSessionView.swift` — complex mode shot type picker**

Add `@State private var showShotTypePicker = false` to `SeriesEditorRow`.

After the "Tirs réussis" stepper block in `SeriesEditorRow.body`, add:
```swift
// Shot type
Button {
    showShotTypePicker = true
} label: {
    HStack {
        Label(series.shotType?.name ?? "Type de tir", systemImage: "figure.basketball")
            .font(.subheadline)
            .foregroundStyle(series.shotType != nil ? Color.orange : .secondary)
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
    }
}
.sheet(isPresented: $showShotTypePicker) {
    ShotTypePickerSheet(selected: Binding(
        get: { series.shotType ?? .catchAndShoot },
        set: { series.shotType = $0 }
    ))
}
```

- [ ] **Step 5: Update `ManualSessionView.save()` for complex mode** — the `ShotSeries` binding already holds `shotType` from `SeriesEditorRow`, so no change needed in `save()`. Verify the template-save path still compiles:
```swift
series.map {
    TemplateSeries(exerciseType: $0.exerciseType,
                   totalShots: $0.totalShots,
                   targetMade: $0.targetMade,
                   shotType: $0.shotType ?? .catchAndShoot)
}
```
Replace the existing `TemplateSeries` map with the above.

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift \
        ios-app/BasketTrainer/Views/RoutineBuilderView.swift \
        ios-app/BasketTrainer/Views/ManualSessionView.swift
git commit -m "feat(ios): add shot type pickers to RoutineBuilderView and ManualSessionView"
```

---

## Task 6: iOS — CourtView + SpotDetailView + ContentView + pbxproj

**Files:**
- Create: `ios-app/BasketTrainer/Views/CourtView.swift`
- Create: `ios-app/BasketTrainer/Views/SpotDetailView.swift`
- Modify: `ios-app/BasketTrainer/Views/ContentView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

### Context

`CourtView` draws a half-court using SwiftUI `Path` + `Canvas`. 9 spots are positioned via normalized coordinates relative to the canvas size. Color encodes `SpotStats.percentage`. `SpotDetailView` receives a `SpotStats` and shows total + per-type bars.

**Spot positions** (normalizedX from 0=left to 1=right, normalizedY from 0=near basket to 1=far/3pt-arc):

| ExerciseType | normX | normY |
|---|---|---|
| freethrow | 0.50 | 0.35 |
| threeCenter | 0.50 | 0.92 |
| threeRight45 | 0.78 | 0.80 |
| threeLeft45 | 0.22 | 0.80 |
| threeCornerR | 0.94 | 0.45 |
| threeCornerL | 0.06 | 0.45 |
| midCenter | 0.50 | 0.62 |
| midRight | 0.70 | 0.56 |
| midLeft | 0.30 | 0.56 |

- [ ] **Step 1: Create `SpotDetailView.swift`**

```swift
import SwiftUI

struct SpotDetailView: View {
    let stats: SpotStats
    @EnvironmentObject var store: SessionStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Global score
                VStack(spacing: 6) {
                    Text("\(stats.totalMade) / \(stats.totalShots)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(String(format: "%.0f%%", stats.percentage))
                        .font(.title2.bold())
                        .foregroundStyle(spotColor(stats.percentage))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemFill))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(spotColor(stats.percentage))
                                .frame(width: geo.size.width * CGFloat(stats.percentage / 100),
                                       height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Per-type breakdown
                if !stats.byType.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Par type de tir")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(ShotType.allCases, id: \.self) { t in
                            if let entry = stats.byType[t] {
                                shotTypeRow(type: t, shots: entry.shots, made: entry.made)
                            }
                        }
                    }
                } else {
                    Text("Pas encore de sessions avec type de tir pour ce spot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding(20)
        }
        .navigationTitle(stats.exerciseType.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shotTypeRow(type: ShotType, shots: Int, made: Int) -> some View {
        let pct = shots == 0 ? 0.0 : Double(made) / Double(shots) * 100
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(type.name).font(.subheadline)
                Spacer()
                Text("\(made)/\(shots)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", pct))
                    .font(.subheadline.bold())
                    .foregroundStyle(spotColor(pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(spotColor(pct))
                        .frame(width: geo.size.width * CGFloat(pct / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spotColor(_ pct: Double) -> Color {
        if pct >= 70 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if pct >= 50 { return .orange }
        return Color(red: 1.0, green: 0.2, blue: 0.2)
    }
}
```

- [ ] **Step 2: Create `CourtView.swift`**

```swift
import SwiftUI

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat  // 0=left 1=right
    let ny: CGFloat  // 0=near basket 1=far
}

private let courtSpots: [CourtSpot] = [
    CourtSpot(type: .freethrow,    nx: 0.50, ny: 0.35),
    CourtSpot(type: .threeCenter,  nx: 0.50, ny: 0.92),
    CourtSpot(type: .threeRight45, nx: 0.78, ny: 0.80),
    CourtSpot(type: .threeLeft45,  nx: 0.22, ny: 0.80),
    CourtSpot(type: .threeCornerR, nx: 0.94, ny: 0.45),
    CourtSpot(type: .threeCornerL, nx: 0.06, ny: 0.45),
    CourtSpot(type: .midCenter,    nx: 0.50, ny: 0.62),
    CourtSpot(type: .midRight,     nx: 0.70, ny: 0.56),
    CourtSpot(type: .midLeft,      nx: 0.30, ny: 0.56),
]

struct CourtView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedSpot: SpotStats? = nil
    @State private var navigating   = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack {
                        // Court background
                        courtShape(w: w, h: h)

                        // Spots
                        ForEach(courtSpots, id: \.type) { spot in
                            let stats   = store.spotStats(for: spot.type)
                            let cx      = spot.nx * w
                            let cy      = (1 - spot.ny) * h * 0.85 + h * 0.05
                            let hasData = stats.totalShots > 0
                            let color   = hasData ? spotColor(stats.percentage) : Color(.systemFill)

                            NavigationLink(destination: SpotDetailView(stats: stats)) {
                                ZStack {
                                    Circle()
                                        .fill(color.opacity(0.9))
                                        .frame(width: 44, height: 44)
                                    Text(hasData
                                         ? String(format: "%.0f%%", stats.percentage)
                                         : "–")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .position(x: cx, y: cy)
                        }
                    }
                }
            }
            .navigationTitle("Terrain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Legend
                    HStack(spacing: 6) {
                        legendDot(Color(red: 0.2, green: 0.8, blue: 0.4), "≥70%")
                        legendDot(.orange, "50%")
                        legendDot(Color(red: 1, green: 0.2, blue: 0.2), "<50%")
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func spotColor(_ pct: Double) -> Color {
        if pct >= 70 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if pct >= 50 { return .orange }
        return Color(red: 1, green: 0.2, blue: 0.2)
    }

    @ViewBuilder
    private func courtShape(w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            let cw = size.width
            let ch = size.height
            let cx = cw / 2

            // Background
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.17, green: 0.35, blue: 0.11)))

            // Court border
            var border = Path()
            border.addRect(CGRect(x: 4, y: 4, width: cw - 8, height: ch - 8))
            ctx.stroke(border, with: .color(.white.opacity(0.5)), lineWidth: 1.5)

            // Paint / raquette (bottom centered)
            let paintW: CGFloat = cw * 0.37
            let paintH: CGFloat = ch * 0.30
            var paint = Path()
            paint.addRect(CGRect(x: cx - paintW/2, y: ch - paintH - 4,
                                 width: paintW, height: paintH))
            ctx.stroke(paint, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            // Free throw circle
            var ftCircle = Path()
            ftCircle.addEllipse(in: CGRect(x: cx - paintW/2, y: ch - paintH - 4 - paintW*0.28,
                                            width: paintW, height: paintW * 0.56))
            ctx.stroke(ftCircle, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            // Basket
            var basket = Path()
            basket.addEllipse(in: CGRect(x: cx - 10, y: ch - 24, width: 20, height: 12))
            ctx.stroke(basket, with: .color(.white), lineWidth: 2)

            // 3pt arc
            var arc = Path()
            arc.move(to: CGPoint(x: 4, y: ch * 0.55))
            arc.addQuadCurve(to: CGPoint(x: cw - 4, y: ch * 0.55),
                             control: CGPoint(x: cx, y: ch * 0.02))
            ctx.stroke(arc, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            // Corner 3pt lines
            var cornerL = Path()
            cornerL.move(to: CGPoint(x: 4, y: ch * 0.55))
            cornerL.addLine(to: CGPoint(x: 4, y: ch - 4))
            ctx.stroke(cornerL, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            var cornerR = Path()
            cornerR.move(to: CGPoint(x: cw - 4, y: ch * 0.55))
            cornerR.addLine(to: CGPoint(x: cw - 4, y: ch - 4))
            ctx.stroke(cornerR, with: .color(.white.opacity(0.4)), lineWidth: 1.5)
        }
    }
}
```

- [ ] **Step 3: Update `ContentView.swift`** — add 4th tab:

```swift
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil",    systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.fill") }
            StatsView()
                .tabItem { Label("Stats",      systemImage: "chart.bar.fill") }
            CourtView()
                .tabItem { Label("Terrain",    systemImage: "sportscourt") }
        }
        .accentColor(.orange)
    }
}
```

- [ ] **Step 4: Register new files in `project.pbxproj`**

Two new files need 4 insertions each (PBXBuildFile, PBXFileReference, Views group, Sources build phase).

Use IDs `AA00000000000000000000E6` (CourtView fileRef), `AA00000000000000000000E7` (CourtView buildFile), `AA00000000000000000000E8` (SpotDetailView fileRef), `AA00000000000000000000E9` (SpotDetailView buildFile).

Add to **PBXBuildFile section** (after the RoutineBuilderView entry):
```
AA00000000000000000000E7 /* CourtView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000E6 /* CourtView.swift */; };
AA00000000000000000000E9 /* SpotDetailView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000E8 /* SpotDetailView.swift */; };
```

Add to **PBXFileReference section** (after RoutineBuilderView.swift entry):
```
AA00000000000000000000E6 /* CourtView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CourtView.swift; sourceTree = "<group>"; };
AA00000000000000000000E8 /* SpotDetailView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpotDetailView.swift; sourceTree = "<group>"; };
```

Add to **Views group children** (after RoutineBuilderView.swift entry):
```
AA00000000000000000000E6 /* CourtView.swift */,
AA00000000000000000000E8 /* SpotDetailView.swift */,
```

Add to **Sources build phase** (after RoutineBuilderView.swift entry):
```
AA00000000000000000000E7 /* CourtView.swift in Sources */,
AA00000000000000000000E9 /* SpotDetailView.swift in Sources */,
```

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Views/CourtView.swift \
        ios-app/BasketTrainer/Views/SpotDetailView.swift \
        ios-app/BasketTrainer/Views/ContentView.swift \
        ios-app/BasketTrainer.xcodeproj/project.pbxproj
git commit -m "feat(ios): add CourtView (4th tab) and SpotDetailView with shot-type breakdown"
```

---

## Self-Review

### Spec coverage
- ✅ `ShotType` enum — Task 1
- ✅ `ShotSeries.shotType?` — Task 1
- ✅ `TemplateSeries.shotType` (mandatory, default `.catchAndShoot`) — Task 1
- ✅ `WorkoutSession.shotType?` — Task 1
- ✅ `SpotStats` + `SessionStore.spotStats(for:)` — Task 1
- ✅ `WorkoutSession.mc` + `GoalSession.mc` shotType — Task 2
- ✅ `ShotTypeMenu.mc` (new) — Task 3
- ✅ `ExerciseMenu.mc` both delegates updated — Task 3
- ✅ `ShotCountMenu.mc` passes shotTypeId to WorkoutSession — Task 3
- ✅ `GoalMenu.mc` passes shotTypeId to GoalSession — Task 3
- ✅ `GoalSummaryView.mc` 4 pops — Task 3
- ✅ `RoutineRunner.mc` currentShotTypeId() — Task 4
- ✅ `GarminManager.sendRoutine()` includes shotTypeId — Task 5
- ✅ `RoutineBuilderView` shot type picker — Task 5
- ✅ `ManualSessionView` shot type picker — Task 5
- ✅ `CourtView.swift` — Task 6
- ✅ `SpotDetailView.swift` — Task 6
- ✅ `ContentView.swift` 4th tab — Task 6
- ✅ pbxproj — Task 6
- ✅ Historical data: `decodeIfPresent` → nil, excluded from byType — Task 1
- ✅ Missing shotTypeId from Garmin → nil via conditional unwrap — Task 1
- ✅ Routine series missing shotTypeId → fallback 0 in `currentShotTypeId()` — Task 4

### No placeholders — all steps have complete code.

### Type consistency
- `new WorkoutSession(exerciseId, totalShots, shotTypeId)` — 3 params everywhere (Tasks 2, 3, 4) ✅
- `new GoalSession(exerciseId, target, shotTypeId)` — 3 params in Task 2 and Task 3 ✅
- `SpotStats.byType: [ShotType: (shots: Int, made: Int)]` — same type in Task 1 and Task 6 ✅
- `ShotTypeMenuDelegate(exerciseId, mode, accumulator)` — used in Task 3 consistently ✅
