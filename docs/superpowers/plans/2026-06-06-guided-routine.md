# Guided Routine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the user to create a multi-series workout routine on iPhone and launch it autonomously on the Garmin FR255, which executes each series in sequence and transmits results back.

**Architecture:** The iPhone sends the full routine as a `{type:"routine", series:[...]}` message to the watch via ConnectIQ SDK. The watch stores it, displays a start screen, then executes each series with `WorkoutView`. After each series, it transmits the result using the existing `transmit()` + `PendingQueue` pipeline, and iPhone's `handleSessionOrGuided` accumulates them into a `ComplexWorkoutSession`.

**Tech Stack:** Swift/SwiftUI (iOS 16+), ConnectIQ iOS SDK 1.8.0, Monkey C / Connect IQ SDK 9.1.0, Garmin Forerunner 255.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `ios-app/BasketTrainer/Views/RoutineBuilderView.swift` | **Create** | Template creation UI (series list + stepper) |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | **Modify** | Add `sendRoutine(_:)` method |
| `ios-app/BasketTrainer/Views/TemplatesView.swift` | **Modify** | Wire "Guider la montre" → `sendRoutine` |
| `ios-app/BasketTrainer/Views/HomeView.swift` | **Modify** | Replace chips section with TemplatesView cards + "+" button |
| `garmin-app/source/BasketApp.mc` | **Modify** | Add `_pendingRoutine`, `onMessage` override, accessors |
| `garmin-app/source/WorkoutView.mc` | **Modify** | Add `_runner` param to `WorkoutDelegate`, 3-way branch in `recordAndAdvance` |
| `garmin-app/source/ShotCountMenu.mc` | **Modify** | Pass `null` as 4th arg to `WorkoutDelegate` |
| `garmin-app/source/RoutineRunner.mc` | **Create** | `RoutineRunner` class + all 5 routine view/delegate pairs |
| `garmin-app/source/MainMenu.mc` | **Modify** | Implement `id == 2` branch |

---

## Task 1: GarminManager.sendRoutine + TemplatesView wire

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift` (after `cancelGuidedSession()`, ~line 140)
- Modify: `ios-app/BasketTrainer/Views/TemplatesView.swift` (~line 125)

- [ ] **Step 1: Add `sendRoutine` to GarminManager**

In `GarminManager.swift`, after the `cancelGuidedSession()` method, add:

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

- [ ] **Step 2: Wire TemplatesView "Guider la montre" button**

In `TemplatesView.swift`, in `TemplatesView.body` inside the `ForEach`, change:

```swift
onLaunchGuided: { garmin.startGuidedSession(template) },
```

to:

```swift
onLaunchGuided: { garmin.sendRoutine(template) },
```

- [ ] **Step 3: Build iOS target**

Open `ios-app/BasketTrainer.xcodeproj` in Xcode. Press `Cmd+B`.
Expected: Build Succeeded, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift \
        ios-app/BasketTrainer/Views/TemplatesView.swift
git commit -m "feat(ios): add sendRoutine to GarminManager, wire TemplateCard guided button"
```

---

## Task 2: RoutineBuilderView + HomeView integration

**Files:**
- Create: `ios-app/BasketTrainer/Views/RoutineBuilderView.swift`
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift`

- [ ] **Step 1: Create RoutineBuilderView.swift**

Create `ios-app/BasketTrainer/Views/RoutineBuilderView.swift` with full content:

```swift
import SwiftUI

struct RoutineBuilderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: SessionStore

    @State private var name = ""
    @State private var seriesList: [TemplateSeries] = [
        TemplateSeries(exerciseType: .freethrow, totalShots: 10)
    ]

    private let maxSeries = 6

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("ex. Matin court", text: $name)
                }
                Section("Séries (\(seriesList.count)/\(maxSeries))") {
                    ForEach(seriesList.indices, id: \.self) { idx in
                        SeriesRow(series: $seriesList[idx])
                    }
                    .onDelete { offsets in
                        seriesList.remove(atOffsets: offsets)
                    }
                    if seriesList.count < maxSeries {
                        Button {
                            seriesList.append(
                                TemplateSeries(exerciseType: .freethrow, totalShots: 10)
                            )
                        } label: {
                            Label("Ajouter une série", systemImage: "plus.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Nouvelle routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sauvegarder") {
                        let template = ComplexTemplate(
                            name: name.isEmpty ? "Routine" : name,
                            series: seriesList
                        )
                        store.addTemplate(template)
                        dismiss()
                    }
                    .disabled(seriesList.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundStyle(seriesList.isEmpty ? .secondary : .orange)
                }
            }
        }
    }
}

struct SeriesRow: View {
    @Binding var series: TemplateSeries
    @State private var showPicker = false

    var body: some View {
        HStack {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(series.exerciseType.emoji)
                    Text(series.exerciseType.name)
                        .foregroundStyle(.primary)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet(selected: $series.exerciseType)
            }
            Spacer()
            Stepper(
                "\(series.totalShots) tirs",
                value: $series.totalShots,
                in: 1...100
            )
            .fixedSize()
        }
    }
}

struct ExercisePickerSheet: View {
    @Binding var selected: ExerciseType
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(ExerciseType.allCases) { type in
                Button {
                    selected = type
                    dismiss()
                } label: {
                    HStack {
                        Text(type.emoji)
                        Text(type.name).foregroundStyle(.primary)
                        Spacer()
                        if selected == type {
                            Image(systemName: "checkmark").foregroundStyle(.orange)
                        }
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
        }
    }
}
```

**Note:** `TemplateSeries` is defined in `Models.swift` as `struct TemplateSeries: Codable { var exerciseType: ExerciseType; var totalShots: Int; var targetMade: Int? }`. The initializer used above (`TemplateSeries(exerciseType:totalShots:)`) works because `targetMade` has a default of `nil`.

- [ ] **Step 2: Update HomeView to show TemplatesView cards + "+" button**

In `HomeView.swift`, add `@State private var showRoutineBuilder = false` alongside the existing state vars (after line 10):

```swift
@State private var showRoutineBuilder = false
```

Replace the entire `templatesSection` computed var (lines 129–166) with:

```swift
private var templatesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text("Routines")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                showRoutineBuilder = true
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.orange)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)

        TemplatesView(onLaunchManual: { t in
            prefillTemplate = t
            showManualEntry = true
        })
        .padding(.horizontal, 20)
    }
}
```

Also add a second `.sheet` modifier on the `NavigationStack` (after the existing `showManualEntry` sheet, around line 61):

```swift
.sheet(isPresented: $showRoutineBuilder) {
    RoutineBuilderView()
        .environmentObject(store)
}
```

- [ ] **Step 3: Add RoutineBuilderView.swift to Xcode project**

In Xcode, right-click the `Views` group → "Add Files to BasketTrainer" → select `RoutineBuilderView.swift`. Ensure "Add to target: BasketTrainer" is checked.

- [ ] **Step 4: Build iOS target**

Press `Cmd+B`.
Expected: Build Succeeded, 0 errors.

- [ ] **Step 5: Smoke-test template creation**

Run in Simulator (`Cmd+R`). On HomeView:
- Tap "+" button in Routines section → `RoutineBuilderView` sheet opens.
- Type a name, adjust stepper, tap "Sauvegarder" → sheet dismisses, template appears in HomeView.
- Tap "Guider la montre" on the card → no crash (guard on `connectedDevice` exits silently if nil).

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Views/RoutineBuilderView.swift \
        ios-app/BasketTrainer/Views/HomeView.swift
git commit -m "feat(ios): add RoutineBuilderView and integrate templates section with guided button"
```

---

## Task 3: BasketApp.mc — message handler

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`

- [ ] **Step 1: Add `_pendingRoutine` and `onMessage` to BasketApp**

Replace the entire content of `BasketApp.mc` with:

```monkey-c
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BasketApp extends Application.AppBase {
    private var _sync           as SyncManager or Null;
    private var _pendingRoutine as Dictionary or Null;

    function initialize() {
        AppBase.initialize();
        _sync           = null;
        _pendingRoutine = null;
    }

    function onStart(state as Dictionary?) as Void {
        _sync = new SyncManager();
        _sync.initialize();
    }

    function onStop(state as Dictionary?) as Void {
        _sync = null;
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }

    // Called when iPhone sends a message via sdk.sendMessage()
    function onMessage(message as Object) as Void {
        var dict = message as Dictionary;
        if (dict["type"] instanceof String && (dict["type"] as String).equals("routine")) {
            _pendingRoutine = dict;
        }
    }

    function getPendingRoutine() as Dictionary or Null {
        return _pendingRoutine;
    }

    function clearPendingRoutine() as Void {
        _pendingRoutine = null;
    }
}

function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
```

- [ ] **Step 2: Build Garmin project**

In VS Code: `Ctrl+Shift+P` → "Monkey C: Build for Device" → select `fr255`.
Expected: Build succeeds, output in `.output/` folder, 0 type errors.

- [ ] **Step 3: Commit**

```bash
git add garmin-app/source/BasketApp.mc
git commit -m "feat(garmin): add onMessage handler and _pendingRoutine storage in BasketApp"
```

---

## Task 4: WorkoutDelegate — add optional runner parameter

**Files:**
- Modify: `garmin-app/source/WorkoutView.mc` (lines 134–183)
- Modify: `garmin-app/source/ShotCountMenu.mc` (line 39)

The `WorkoutDelegate` currently takes 3 params `(session, view, accumulator)`. We add a 4th: `runner as RoutineRunner or Null`. When runner is non-null, after the last shot it calls `runner.onSeriesComplete(session)` and pushes `RoutineSeriesDoneView` instead of the accumulator or summary paths.

**Note:** `RoutineRunner`, `RoutineSeriesDoneView`, `RoutineSeriesDoneDelegate` are defined in `RoutineRunner.mc` (Task 5). Monkey C resolves classes across files at compile time — adding the forward-reference here won't cause a build error as long as `RoutineRunner.mc` exists before the final build. Add it in Task 5 immediately after.

- [ ] **Step 1: Add `_runner` field and update `initialize` in WorkoutDelegate**

In `WorkoutView.mc`, replace the `WorkoutDelegate` class (lines 134–183) with:

```monkey-c
class WorkoutDelegate extends WatchUi.BehaviorDelegate {
    private var _session     as WorkoutSession;
    private var _accumulator as SessionAccumulator or Null;
    private var _runner      as RoutineRunner or Null;

    function initialize(session     as WorkoutSession,
                        view        as WorkoutView,
                        accumulator as SessionAccumulator or Null,
                        runner      as RoutineRunner or Null) {
        BehaviorDelegate.initialize();
        _session     = session;
        _accumulator = accumulator;
        _runner      = runner;
    }

    function onNextPage() as Boolean {
        recordAndAdvance(true);
        return true;
    }

    function onPreviousPage() as Boolean {
        recordAndAdvance(false);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function recordAndAdvance(made as Boolean) as Void {
        _session.recordShot(made);

        if (_session.isFinished()) {
            if (_runner != null) {
                // Routine mode: transmit, advance runner, show bridge view
                var runner     = _runner as RoutineRunner;
                var completedN = runner.seriesNumber();
                runner.onSeriesComplete(_session);
                var doneView = new RoutineSeriesDoneView(_session, runner, completedN);
                var doneDel  = new RoutineSeriesDoneDelegate(runner);
                WatchUi.pushView(doneView, doneDel, WatchUi.SLIDE_LEFT);
            } else if (_accumulator != null) {
                // Free multi-series mode
                var acc = _accumulator as SessionAccumulator;
                acc.addSeries(_session);
                var doneView = new SeriesDoneView(_session, acc);
                var doneDel  = new SeriesDoneDelegate(acc);
                WatchUi.pushView(doneView, doneDel, WatchUi.SLIDE_LEFT);
            } else {
                // Simple single-series mode
                var summaryView = new SummaryView(_session);
                var summaryDel  = new SummaryDelegate(_session);
                WatchUi.pushView(summaryView, summaryDel, WatchUi.SLIDE_LEFT);
            }
        } else {
            WatchUi.requestUpdate();
        }
    }
}
```

- [ ] **Step 2: Update ShotCountMenuDelegate to pass `null` as 4th arg**

In `ShotCountMenu.mc`, replace line 39:

```monkey-c
var delegate   = new WorkoutDelegate(session, view, _accumulator);
```

with:

```monkey-c
var delegate   = new WorkoutDelegate(session, view, _accumulator, null);
```

- [ ] **Step 3: Build Garmin project**

`Ctrl+Shift+P` → "Monkey C: Build for Device".
Expected: One type error about unknown class `RoutineRunner` is acceptable at this stage — it will be resolved in Task 5. If there are other errors, fix them first.

- [ ] **Step 4: Commit**

```bash
git add garmin-app/source/WorkoutView.mc \
        garmin-app/source/ShotCountMenu.mc
git commit -m "feat(garmin): add optional RoutineRunner param to WorkoutDelegate"
```

---

## Task 5: RoutineRunner.mc — new file with all routine views

**Files:**
- Create: `garmin-app/source/RoutineRunner.mc`

This single file contains: `RoutineRunner`, `RoutineWaitView/Delegate`, `RoutineStartView/Delegate`, `RoutineSeriesDoneView/Delegate`, `RoutineFinalView/Delegate`.

- [ ] **Step 1: Create RoutineRunner.mc**

Create `garmin-app/source/RoutineRunner.mc` with full content:

```monkey-c
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// RoutineRunner — drives a pre-defined series sequence
// ─────────────────────────────────────────────────

class RoutineRunner {
    private var _series as Array;   // [{exerciseId, totalShots}]
    private var _index  as Number;  // current position (0-based)
    var accumulator     as SessionAccumulator;

    function initialize(routine as Dictionary) {
        _series     = routine["series"] as Array;
        _index      = 0;
        accumulator = new SessionAccumulator();
    }

    function currentExerciseId() as Number {
        return (_series[_index] as Dictionary)["exerciseId"] as Number;
    }

    function currentTotalShots() as Number {
        return (_series[_index] as Dictionary)["totalShots"] as Number;
    }

    function exerciseIdAt(i as Number) as Number {
        return (_series[i] as Dictionary)["exerciseId"] as Number;
    }

    function totalShotsAt(i as Number) as Number {
        return (_series[i] as Dictionary)["totalShots"] as Number;
    }

    function seriesNumber() as Number { return _index + 1; }  // 1-based

    function totalSeries() as Number { return _series.size(); }

    function isComplete() as Boolean { return _index >= _series.size(); }

    function totalPlannedShots() as Number {
        var t = 0;
        for (var i = 0; i < _series.size(); i++) {
            t += (_series[i] as Dictionary)["totalShots"] as Number;
        }
        return t;
    }

    // Store result, transmit to iPhone, advance index
    function onSeriesComplete(session as WorkoutSession) as Void {
        accumulator.addSeries(session);
        var dict = session.toDictionary();
        Communications.transmit(dict, null, new TransmitListener(dict));
        _index++;
    }
}

// ─────────────────────────────────────────────────
// RoutineWaitView — shown when no routine is pending
// ─────────────────────────────────────────────────

class RoutineWaitView extends WatchUi.View {
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize() { View.initialize(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90,  Graphics.FONT_TINY,  "Aucune routine",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 118, Graphics.FONT_XTINY, "Ouvre l'app iPhone",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 136, Graphics.FONT_XTINY, "et appuie sur",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 154, Graphics.FONT_XTINY, "\"Guider la montre\"",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 215, Graphics.FONT_XTINY, "↩ Retour",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineWaitDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineStartView — routine overview before starting
// ─────────────────────────────────────────────────

class RoutineStartView extends WatchUi.View {
    private var _runner    as RoutineRunner;
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize(runner as RoutineRunner) {
        View.initialize();
        _runner = runner;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Routine guidée"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 24, Graphics.FONT_XTINY, "Routine guidée",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "N séries · X tirs"
        var header = _runner.totalSeries().toString() + " séries · "
                   + _runner.totalPlannedShots().toString() + " tirs";
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_TINY, header,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // List each series (up to 6)
        var n = _runner.totalSeries();
        for (var i = 0; i < n && i < 6; i++) {
            var line = (i + 1).toString() + ". "
                     + getExerciseName(_runner.exerciseIdAt(i))
                     + " ×" + _runner.totalShotsAt(i).toString();
            dc.setColor(i == 0 ? COLOR_ORANGE : COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 76 + i * 20, Graphics.FONT_XTINY, line,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instruction
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 224, Graphics.FONT_XTINY, "▶ START = commencer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineStartDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean {
        var sess = new WorkoutSession(_runner.currentExerciseId(), _runner.currentTotalShots());
        var view = new WorkoutView(sess, null);
        var del  = new WorkoutDelegate(sess, view, null, _runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineSeriesDoneView — inter-series bridge screen
// ─────────────────────────────────────────────────

class RoutineSeriesDoneView extends WatchUi.View {
    private var _session    as WorkoutSession;
    private var _runner     as RoutineRunner;
    private var _completedN as Number;  // 1-based series number just finished

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session    as WorkoutSession,
                        runner     as RoutineRunner,
                        completedN as Number) {
        View.initialize();
        _session    = session;
        _runner     = runner;
        _completedN = completedN;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Série X/N terminée"
        var label = "Série " + _completedN.toString()
                  + "/" + _runner.totalSeries().toString() + " terminée";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Exercise name
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score
        var score = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 94, Graphics.FONT_NUMBER_MEDIUM, score,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Percentage
        var pct      = _session.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Separator
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(40, 156, w - 40, 156);

        // Next series info or "last series" message
        if (!_runner.isComplete()) {
            var nextName  = getExerciseName(_runner.currentExerciseId());
            var nextShots = _runner.currentTotalShots();
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 172, Graphics.FONT_XTINY, "→ " + nextName,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 188, Graphics.FONT_XTINY,
                        "×" + nextShots.toString() + " tirs",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 178, Graphics.FONT_XTINY, "Dernière série !",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instructions
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 209, Graphics.FONT_XTINY,
                    _runner.isComplete() ? "▶ Résumé final" : "▶ Continuer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 228, Graphics.FONT_XTINY, "↩ Abandonner",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineSeriesDoneDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean {
        if (_runner.isComplete()) {
            var view = new RoutineFinalView(_runner);
            var del  = new RoutineFinalDelegate(_runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        } else {
            var sess = new WorkoutSession(_runner.currentExerciseId(), _runner.currentTotalShots());
            var view = new WorkoutView(sess, null);
            var del  = new WorkoutDelegate(sess, view, null, _runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    // BACK = abandon → show final with partial results
    function onBack() as Boolean {
        var view = new RoutineFinalView(_runner);
        var del  = new RoutineFinalDelegate(_runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineFinalView — global summary (no re-send needed)
// ─────────────────────────────────────────────────

class RoutineFinalView extends WatchUi.View {
    private var _runner as RoutineRunner;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(runner as RoutineRunner) {
        View.initialize();
        _runner = runner;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w   = dc.getWidth();
        var cx  = w / 2;
        var acc = _runner.accumulator;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Séance terminée"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, Graphics.FONT_XTINY, "Séance terminée",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "N séries"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_XTINY,
                    acc.seriesCount().toString() + " séries",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Total score
        var scoreText = acc.totalMade().toString() + " / " + acc.totalShots().toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 94, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Percentage
        var pct      = acc.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Duration
        var elapsed = acc.elapsedSeconds();
        var mins    = elapsed / 60;
        var secs    = elapsed % 60;
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 163, Graphics.FONT_XTINY,
                    mins.format("%d") + "min " + secs.format("%02d") + "s",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "Terminer" (no send button — each series was already transmitted)
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 208, Graphics.FONT_XTINY, "▶ Terminer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineFinalDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean { popToRoot(); return true; }
    function onBack()   as Boolean { popToRoot(); return true; }

    private function popToRoot() as Void {
        // Stack at this point: MainMenu + RoutineStart
        //   + K × (WorkoutView + RoutineSeriesDoneView) + RoutineFinalView
        // Total pops needed = 2K + 2  (K completed series)
        var k    = _runner.accumulator.seriesCount();
        var pops = k * 2 + 2;
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
```

- [ ] **Step 2: Build Garmin project**

`Ctrl+Shift+P` → "Monkey C: Build for Device".
Expected: Build succeeds, 0 errors. The `RoutineRunner` class reference in `WorkoutView.mc` now resolves correctly.

- [ ] **Step 3: Commit**

```bash
git add garmin-app/source/RoutineRunner.mc
git commit -m "feat(garmin): add RoutineRunner.mc with all routine views and delegates"
```

---

## Task 6: MainMenu.mc — wire "Objectif complexe"

**Files:**
- Modify: `garmin-app/source/MainMenu.mc`

- [ ] **Step 1: Implement the `id == 2` branch**

In `MainMenu.mc`, replace the `onSelect` method of `MainMenuDelegate` with:

```monkey-c
function onSelect(item as WatchUi.MenuItem) as Void {
    var id = item.getId() as Number;
    if (id == 0) {
        var menu = new ExerciseMenuView();
        var del  = new ExerciseMenuDelegate(null);
        WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
    } else if (id == 1) {
        var menu = new ExerciseMenuView();
        var del  = new ExerciseMenuGoalDelegate();
        WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
    } else {
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
}
```

- [ ] **Step 2: Build Garmin project**

`Ctrl+Shift+P` → "Monkey C: Build for Device".
Expected: Build succeeds, 0 errors, 0 type warnings beyond the pre-existing `transmit` dictionary warning.

- [ ] **Step 3: Simulator smoke-test**

1. Launch the Garmin simulator (`simulator.exe`)
2. Load the built `.prg`
3. Navigate to "Objectif complexe" → expected: `RoutineWaitView` showing "Aucune routine".
4. Press BACK → returns to main menu.

- [ ] **Step 4: Commit**

```bash
git add garmin-app/source/MainMenu.mc
git commit -m "feat(garmin): implement Objectif complexe branch in MainMenu"
```

---

## Task 7: End-to-end test

No code changes — this task validates the full flow manually.

- [ ] **Step 1: Build both targets**

- iOS: `Cmd+B` in Xcode → Build Succeeded
- Garmin: `Ctrl+Shift+P` → "Monkey C: Build for Device" → success

- [ ] **Step 2: iPhone flow test (Simulator)**

1. Run iOS app in Simulator (`Cmd+R`)
2. Tap "+" in Routines section → `RoutineBuilderView` opens
3. Set name "Test", add 2 series: Lancer Franc ×5, 3pts Centre ×10
4. Tap "Sauvegarder" → sheet closes, template appears in HomeView
5. Tap "Guider la montre" on the card → no crash (exits guard since no real watch)
6. Verify `store.templates` has the new template (check session store via debug or HomeView display)

- [ ] **Step 3: Garmin simulator flow test**

1. Load `.prg` in Garmin simulator
2. Navigate Main Menu → "Objectif complexe" → `RoutineWaitView` shown ✓
3. To simulate receiving a routine, temporarily add hardcoded `_pendingRoutine` to `BasketApp.initialize()` for testing:
   ```monkey-c
   _pendingRoutine = {
       "type" => "routine",
       "series" => [
           {"exerciseId" => 0, "totalShots" => 5},
           {"exerciseId" => 1, "totalShots" => 5}
       ]
   };
   ```
4. Rebuild, reload → "Objectif complexe" should now show `RoutineStartView` with 2 séries · 10 tirs
5. Press SELECT → `WorkoutView` for Lancer Franc ×5
6. Record 5 shots (UP/DOWN) → `RoutineSeriesDoneView` shows "Série 1/2 terminée"
7. Press SELECT → `WorkoutView` for 3pts Centre ×5
8. Record 5 shots → `RoutineSeriesDoneView` shows "Dernière série !"
9. Press SELECT → `RoutineFinalView` with total score
10. Press SELECT → returns to MainMenu ✓
11. Remove the hardcoded `_pendingRoutine` from `initialize()` after testing

- [ ] **Step 4: Final commit (remove test harness)**

```bash
git add garmin-app/source/BasketApp.mc
git commit -m "test(garmin): remove hardcoded _pendingRoutine test harness"
```

---

## Self-Review Checklist

- [x] **Spec coverage:**
  - ✓ iPhone routine builder (Task 2)
  - ✓ `sendRoutine` sends via ConnectIQ SDK (Task 1)
  - ✓ `startGuidedSession` called to enable iPhone accumulation (Task 1)
  - ✓ Garmin `onMessage` stores routine (Task 3)
  - ✓ `RoutineStartView` shows overview (Task 5)
  - ✓ Each series runs via `WorkoutView` (Task 4)
  - ✓ After each series: `transmit()` + `PendingQueue` fallback (Task 5, `onSeriesComplete`)
  - ✓ `RoutineSeriesDoneView` shows next exercise (Task 5)
  - ✓ `RoutineFinalView` shows global summary (Task 5)
  - ✓ `MainMenu` id==2 branch (Task 6)
  - ✓ Max 6 series enforced in builder (Task 2)
  - ✓ Free-form shot count 1–100 (Task 2, stepper)
  - ✓ No new exercise types (spec decision, no changes to ExerciseType)

- [x] **Type consistency:**
  - `WorkoutDelegate.initialize` signature: `(session, view, accumulator, runner)` — used consistently in Tasks 4, 5
  - `RoutineRunner.onSeriesComplete` increments `_index` after storing — `isComplete()` / `currentExerciseId()` called after increment in `RoutineSeriesDoneView` ✓
  - `addTemplate(_:)` is the correct `SessionStore` method name (confirmed in code) ✓
  - `getApp().getPendingRoutine()` / `clearPendingRoutine()` — defined in Task 3, used in Task 6 ✓
