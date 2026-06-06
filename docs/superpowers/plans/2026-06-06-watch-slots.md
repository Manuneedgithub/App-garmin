# Watch Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ephemeral "pending routine" system with 5 persistent training slots stored on the watch via `Application.Storage`, configurable from a new `SlotsView` on iPhone.

**Architecture:** Three layers of change — (1) Garmin watch replaces `_pendingRoutine` with `Application.Storage`-backed slots and adds a new `SlotMenu` screen, (2) iOS `SessionStore` + `GarminManager` replace guided-session tracking with a simple `sendSlot()` method, (3) a new `SlotsView` with per-slot editor replaces the old guided-session UI.

**Tech Stack:** Monkey C / Connect IQ SDK 9.1.0 (Garmin), Swift / SwiftUI iOS 16+ (iPhone), `Application.Storage` (watch persistence), UserDefaults/JSONEncoder (iPhone persistence).

---

## File Map

| File | Action |
|---|---|
| `garmin-app/source/BasketApp.mc` | Modify — remove `_pendingRoutine`, add slot storage in `onMessage` |
| `garmin-app/source/MainMenu.mc` | Modify — rename item 2, wire to `SlotMenu`, remove `RoutineWait` classes |
| `garmin-app/source/SlotMenu.mc` | **Create** — `SlotMenuView`, `SlotMenuDelegate`, `SlotEmptyView/Delegate` |
| `garmin-app/source/RoutineRunner.mc` | Modify — remove `RoutineWaitView/Delegate`, fix pop count (+1 for SlotMenu) |
| `ios-app/BasketTrainer/Models/SessionStore.swift` | Modify — add `watchSlots` array + persistence |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Modify — remove guided tracking, add `sendSlot()`, simplify `parseAndStore` |
| `ios-app/BasketTrainer/Views/SlotsView.swift` | **Create** — slot cards + `SlotEditorView` |
| `ios-app/BasketTrainer/Views/HomeView.swift` | Modify — remove `GuidedSessionBanner`, add "Configurer" button |
| `ios-app/BasketTrainer/Views/TemplatesView.swift` | Modify — remove `GuidedSessionBanner` struct |
| `ios-app/BasketTrainer.xcodeproj/project.pbxproj` | Modify — register `SlotsView.swift` |

---

## Task 1: Garmin — Slot Storage + SlotMenu

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`
- Create: `garmin-app/source/SlotMenu.mc`
- Modify: `garmin-app/source/MainMenu.mc`
- Modify: `garmin-app/source/RoutineRunner.mc`

### Context

`BasketApp.mc` currently holds `_pendingRoutine as Dictionary or Null` in memory (lost on watch restart). `onMessage` sets this field when it receives `type=="routine"`. We replace the whole mechanism:
- `onMessage` now handles `type=="slot"` and writes to `Application.Storage` (key `"slot_0"` … `"slot_4"`)
- `MainMenu.mc` item id=2 ("Objectif complexe") is renamed "Entraînements" and pushed to the new `SlotMenuView`
- `SlotMenu.mc` reads from `Application.Storage` and either launches `RoutineRunner` (if slot has data) or `SlotEmptyView`
- `RoutineRunner.mc`: remove the `RoutineWaitView`/`RoutineWaitDelegate` classes (lines 64–97 in the current file); fix `RoutineFinalDelegate.popToRoot()` — the stack now includes SlotMenu so the formula changes from `k*2+2` to `k*2+3`

- [ ] **Step 1: Rewrite `BasketApp.mc`** — remove `_pendingRoutine`, `getPendingRoutine`, `clearPendingRoutine`; update `onMessage` to write to `Application.Storage`:

```monkey-c
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BasketApp extends Application.AppBase {
    private var _sync as SyncManager or Null;

    function initialize() {
        AppBase.initialize();
        _sync = null;
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

    function onMessage(message as Object) as Void {
        if (!(message instanceof Dictionary)) { return; }
        var dict = message as Dictionary;
        if (dict["type"] instanceof String && (dict["type"] as String).equals("slot")) {
            var index  = dict["index"] as Number;
            var series = dict["series"] as Array;
            Application.Storage.setValue("slot_" + index.toString(), series);
        }
    }
}

function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
```

- [ ] **Step 2: Create `garmin-app/source/SlotMenu.mc`**:

```monkey-c
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Application;

// Returns "X séries · Y tirs" if slot has data, null if empty
function slotSummary(index as Number) as String or Null {
    var val = Application.Storage.getValue("slot_" + index.toString());
    if (val == null) { return null; }
    var arr   = val as Array;
    var total = 0;
    for (var i = 0; i < arr.size(); i++) {
        total += (arr[i] as Dictionary)["totalShots"] as Number;
    }
    return arr.size().toString() + " séries · " + total.toString() + " tirs";
}

class SlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Entraînements"});
        for (var i = 0; i < 5; i++) {
            var label = "Entr. " + (i + 1).toString();
            var sub   = slotSummary(i);
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class SlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index  = item.getId() as Number;
        var series = Application.Storage.getValue("slot_" + index.toString());
        if (series == null) {
            WatchUi.pushView(new SlotEmptyView(), new SlotEmptyDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            var routine = {"series" => series as Array} as Dictionary;
            var runner  = new RoutineRunner(routine);
            var view    = new RoutineStartView(runner);
            var del     = new RoutineStartDelegate(runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class SlotEmptyView extends WatchUi.View {
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize() { View.initialize(); }
    function onLayout(dc as Graphics.Dc) as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90, Graphics.FONT_TINY, "Slot vide",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 118, Graphics.FONT_XTINY, "Configure depuis",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 136, Graphics.FONT_XTINY, "l'app iPhone",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 215, Graphics.FONT_XTINY, "↩ Retour",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class SlotEmptyDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
```

- [ ] **Step 3: Update `MainMenu.mc`**

  A) In `MainMenuView.initialize()`, change the third `addItem` label and rename the item:

  Replace:
  ```monkey-c
  addItem(new WatchUi.MenuItem("Objectif complexe", null, 2, null));
  ```
  With:
  ```monkey-c
  addItem(new WatchUi.MenuItem("Entraînements",    null, 2, null));
  ```

  B) In `MainMenuDelegate.onSelect`, replace the entire `else if (id == 2)` block:
  ```monkey-c
  } else if (id == 2) {
      var menu = new SlotMenuView();
      var del  = new SlotMenuDelegate();
      WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
  }
  ```

  C) Delete `RoutineWaitView` and `RoutineWaitDelegate` classes — they are at the bottom of `MainMenu.mc`. (Search for `class RoutineWaitView` and remove through the closing `}` of `RoutineWaitDelegate`.)

  **Note:** Read the actual file first to confirm RoutineWait is in MainMenu.mc or RoutineRunner.mc — it may be in either.

- [ ] **Step 4: Update `RoutineRunner.mc`**

  A) Remove `RoutineWaitView` and `RoutineWaitDelegate` classes (currently lines 64–97). These are the classes that showed "Aucune routine / Ouvre l'app iPhone". Delete from `class RoutineWaitView` through the closing `}` of `RoutineWaitDelegate`.

  B) In `RoutineFinalDelegate.popToRoot()`, change the pop formula — SlotMenu is now on the stack between MainMenu and RoutineStartView, adding 1 more pop:

  Replace:
  ```monkey-c
  var pops = k * 2 + 2;
  ```
  With:
  ```monkey-c
  var pops = k * 2 + 3;
  ```

  Also update the comment:
  ```monkey-c
  // Stack: MainMenu + SlotMenu + RoutineStart
  //   + K × (WorkoutView + RoutineSeriesDoneView) + RoutineFinalView
  // Total pops = 2K + 3
  ```

- [ ] **Step 5: Commit**

```bash
git add garmin-app/source/BasketApp.mc \
        garmin-app/source/SlotMenu.mc \
        garmin-app/source/MainMenu.mc \
        garmin-app/source/RoutineRunner.mc
git commit -m "feat(garmin): replace pending routine with 5 persistent watch slots"
```

---

## Task 2: iOS — SessionStore + GarminManager

**Files:**
- Modify: `ios-app/BasketTrainer/Models/SessionStore.swift`
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

### Context

`SessionStore` gains a `watchSlots: [ComplexTemplate?]` array (5 entries, nil = empty) persisted in UserDefaults under key `"basket_watch_slots"`.

`GarminManager` loses all guided-session tracking (`guidedTemplate`, `guidedIndex`, `guidedSeries`, `startGuidedSession`, `cancelGuidedSession`, `handleSessionOrGuided`) and `sendRoutine`. It gains `sendSlot(_ index:, template:)`. `parseAndStore` is simplified to always call `store.add(session)` directly.

- [ ] **Step 1: Add `watchSlots` to `SessionStore.swift`**

  After the existing `@Published private(set) var templates` line, add:
  ```swift
  @Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: 5)
  private let slotsKey = "basket_watch_slots"
  ```

  After `func deleteTemplate(_ t: ComplexTemplate)`, add the new methods:
  ```swift
  func setWatchSlot(_ index: Int, template: ComplexTemplate?) {
      guard index >= 0 && index < 5 else { return }
      watchSlots[index] = template
      saveSlots()
  }

  private func saveSlots() {
      if let data = try? JSONEncoder().encode(watchSlots) {
          UserDefaults.standard.set(data, forKey: slotsKey)
      }
  }

  private func loadSlots() {
      guard let data = UserDefaults.standard.data(forKey: slotsKey),
            let decoded = try? JSONDecoder().decode([ComplexTemplate?].self, from: data)
      else { return }
      watchSlots = decoded
  }
  ```

  In `init()`, add `loadSlots()` after `loadTemplates()`:
  ```swift
  init() {
      load()
      loadTemplates()
      loadSlots()
  }
  ```

- [ ] **Step 2: Simplify `GarminManager.swift`**

  **Remove** these `@Published` properties:
  ```swift
  @Published var guidedTemplate: ComplexTemplate? = nil
  @Published var guidedIndex: Int = 0
  @Published var guidedSeries: [ShotSeries] = []
  ```

  **Remove** these methods entirely:
  - `func startGuidedSession(_ template: ComplexTemplate)`
  - `func cancelGuidedSession()`
  - `func handleSessionOrGuided(_ session: WorkoutSession, results: [Bool], total: Int, made: Int)`
  - `func sendRoutine(_ template: ComplexTemplate)`

  **Simplify `parseAndStore`** — replace the `DispatchQueue.main.async` block at the end:

  Replace:
  ```swift
  DispatchQueue.main.async {
      self.lastSyncDate = Date()
      self.handleSessionOrGuided(session, results: rawResults, total: total, made: made)
  }
  ```
  With:
  ```swift
  DispatchQueue.main.async {
      self.lastSyncDate = Date()
      self.store.add(session)
  }
  ```

  **Add `sendSlot`** after `connectWatch()`:
  ```swift
  func sendSlot(_ index: Int, template: ComplexTemplate) {
      guard let device = connectedDevice else { return }
      let app = IQApp(uuid: appUUID, store: appUUID, device: device)
      let payload: [String: Any] = [
          "type": "slot",
          "index": index,
          "series": template.series.map {
              [
                  "exerciseId": $0.exerciseType.rawValue,
                  "totalShots": $0.totalShots,
                  "shotTypeId": $0.shotType.rawValue
              ]
          }
      ]
      sdk.sendMessage(payload, to: app, progress: nil) { _ in }
  }
  ```

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Models/SessionStore.swift \
        ios-app/BasketTrainer/Managers/GarminManager.swift
git commit -m "feat(ios): add watchSlots to SessionStore, replace sendRoutine with sendSlot"
```

---

## Task 3: iOS — SlotsView + HomeView + TemplatesView + pbxproj

**Files:**
- Create: `ios-app/BasketTrainer/Views/SlotsView.swift`
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift`
- Modify: `ios-app/BasketTrainer/Views/TemplatesView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

### Context

`SlotsView` shows 5 `SlotCard` views. Each card shows the slot's series list (or "(vide)") plus "Modifier" and "Envoyer ▶" buttons. Tapping "Modifier" opens `SlotEditorView` as a sheet — a `Form` with `SeriesRow` entries (reusing the component from `RoutineBuilderView.swift`) and a "Sauvegarder" / "Effacer le slot" toolbar.

`HomeView` loses the `GuidedSessionBanner` block and gains a "Configurer la montre" button that opens `SlotsView` as a sheet.

`TemplatesView` has `GuidedSessionBanner` defined at the bottom — delete that struct.

`SlotsView.swift` gets pbxproj IDs: `AA00000000000000000000EA` (fileRef) / `AA00000000000000000000EB` (buildFile).

- [ ] **Step 1: Create `ios-app/BasketTrainer/Views/SlotsView.swift`**

```swift
import SwiftUI

private struct SlotEditRequest: Identifiable {
    let id: Int
}

struct SlotsView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editRequest: SlotEditRequest? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { i in
                        SlotCard(
                            index: i,
                            template: store.watchSlots[i],
                            isConnected: garmin.connectedDevice != nil,
                            onEdit: { editRequest = SlotEditRequest(id: i) },
                            onSend: {
                                if let t = store.watchSlots[i] {
                                    garmin.sendSlot(i, template: t)
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Entraînements montre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
        .sheet(item: $editRequest) { req in
            SlotEditorView(index: req.id, existing: store.watchSlots[req.id])
                .environmentObject(store)
        }
    }
}

private struct SlotCard: View {
    let index:       Int
    let template:    ComplexTemplate?
    let isConnected: Bool
    let onEdit:      () -> Void
    let onSend:      () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Entraînement \(index + 1)")
                    .font(.headline)
                Spacer()
                if let t = template {
                    Text("\(t.series.count) séries")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }

            if let t = template {
                ForEach(t.series.indices, id: \.self) { j in
                    HStack(spacing: 6) {
                        Text(t.series[j].exerciseType.emoji)
                        Text(t.series[j].exerciseType.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(t.series[j].totalShots) tirs")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(t.series[j].shotType.name)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                Text("(vide — appuyer sur Modifier pour configurer)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Modifier", action: onEdit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)

                Spacer()

                Button(action: onSend) {
                    Label("Envoyer", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(template != nil && isConnected ? Color.orange : Color(.systemFill))
                        .clipShape(Capsule())
                }
                .disabled(template == nil || !isConnected)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SlotEditorView: View {
    let index: Int
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var seriesList: [TemplateSeries]
    private let maxSeries = 6

    init(index: Int, existing: ComplexTemplate?) {
        self.index = index
        _seriesList = State(initialValue:
            existing?.series ?? [TemplateSeries(exerciseType: .freethrow, totalShots: 10)]
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Séries (\(seriesList.count)/\(maxSeries))") {
                    ForEach(seriesList.indices, id: \.self) { idx in
                        SeriesRow(series: $seriesList[idx])
                    }
                    .onDelete { offsets in seriesList.remove(atOffsets: offsets) }
                    if seriesList.count < maxSeries {
                        Button {
                            seriesList.append(TemplateSeries(exerciseType: .freethrow, totalShots: 10))
                        } label: {
                            Label("Ajouter une série", systemImage: "plus.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    Button("Effacer le slot") {
                        store.setWatchSlot(index, template: nil)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Entraînement \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sauvegarder") {
                        let t = ComplexTemplate(
                            name: "Entraînement \(index + 1)",
                            series: seriesList
                        )
                        store.setWatchSlot(index, template: t)
                        dismiss()
                    }
                    .disabled(seriesList.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Update `HomeView.swift`**

  A) Remove the `GuidedSessionBanner` block (lines 21–25 in the current file):
  ```swift
  // DELETE this block:
  if garmin.guidedTemplate != nil {
      GuidedSessionBanner()
          .padding(.horizontal, 20)
          .transition(.move(edge: .top).combined(with: .opacity))
  }
  ```

  B) Remove the `.animation` modifier on the `VStack` (currently `.animation(.easeInOut(duration: 0.3), value: garmin.guidedTemplate != nil)`).

  C) Add `@State private var showSlotsConfig = false` alongside the other `@State` vars at the top.

  D) After the `watchConnectionRow.padding(.horizontal, 20)` line, insert a "Configurer la montre" button:
  ```swift
  Button {
      showSlotsConfig = true
  } label: {
      HStack {
          Image(systemName: "dumbbell.fill")
              .foregroundStyle(.orange)
          Text("Configurer les entraînements montre")
              .font(.subheadline)
              .foregroundStyle(.primary)
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
  .padding(.horizontal, 20)
  ```

  E) Add the sheet at the end of the `.sheet` chain (after the `showRoutineBuilder` sheet):
  ```swift
  .sheet(isPresented: $showSlotsConfig) {
      SlotsView()
          .environmentObject(store)
          .environmentObject(garmin)
  }
  ```

- [ ] **Step 3: Remove `GuidedSessionBanner` from `TemplatesView.swift`**

  Delete the entire `GuidedSessionBanner` struct (from `struct GuidedSessionBanner: View {` to its closing `}`). It's at the bottom of the file starting around line 167. It references `garmin.guidedTemplate`, `garmin.guidedIndex`, `garmin.cancelGuidedSession()` — all of which no longer exist.

- [ ] **Step 4: Register `SlotsView.swift` in `project.pbxproj`**

  Use IDs `AA00000000000000000000EA` (fileRef) and `AA00000000000000000000EB` (buildFile).

  Add to **PBXBuildFile section** (after the SpotDetailView entry `AA00000000000000000000E9`):
  ```
  		AA00000000000000000000EB /* SlotsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000EA /* SlotsView.swift */; };
  ```

  Add to **PBXFileReference section** (after the SpotDetailView entry `AA00000000000000000000E8`):
  ```
  		AA00000000000000000000EA /* SlotsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SlotsView.swift; sourceTree = "<group>"; };
  ```

  Add to **Views group children** (after `AA00000000000000000000E8 /* SpotDetailView.swift */`):
  ```
  			AA00000000000000000000EA /* SlotsView.swift */,
  ```

  Add to **Sources build phase** (after `AA00000000000000000000E9 /* SpotDetailView.swift in Sources */`):
  ```
  			AA00000000000000000000EB /* SlotsView.swift in Sources */,
  ```

- [ ] **Step 5: Commit**

```bash
git add ios-app/BasketTrainer/Views/SlotsView.swift \
        ios-app/BasketTrainer/Views/HomeView.swift \
        ios-app/BasketTrainer/Views/TemplatesView.swift \
        ios-app/BasketTrainer.xcodeproj/project.pbxproj
git commit -m "feat(ios): add SlotsView with 5 configurable watch training slots"
```

---

## Self-Review

### Spec coverage
- ✅ 5 fixed slots "Entraînement 1–5" — `SlotMenuView` (Task 1)
- ✅ Watch persistence via `Application.Storage` — `BasketApp.onMessage` + `SlotMenuDelegate` (Task 1)
- ✅ Empty slot shown but non-launchable → `SlotEmptyView` (Task 1)
- ✅ `{"type": "slot", "index": N, "series": [...]}` protocol — `BasketApp.onMessage` + `GarminManager.sendSlot` (Tasks 1+2)
- ✅ iPhone slot storage in UserDefaults — `SessionStore.watchSlots` + `saveSlots/loadSlots` (Task 2)
- ✅ `sendSlot()` replaces `sendRoutine()` — (Task 2)
- ✅ Guided tracking removed — `GarminManager` cleanup (Task 2)
- ✅ Each series stored as individual `WorkoutSession` — `parseAndStore` simplification (Task 2)
- ✅ `SlotsView` with 5 cards + editor — (Task 3)
- ✅ "Configurer la montre" button in `HomeView` — (Task 3)
- ✅ `GuidedSessionBanner` removed — (Task 3)
- ✅ pbxproj registered — (Task 3)
- ✅ Pop count fixed +1 for SlotMenu — `RoutineFinalDelegate.popToRoot()` (Task 1)

### Type consistency
- `ComplexTemplate(name:, series:)` — used in `SlotEditorView` and `SessionStore.setWatchSlot` ✅
- `store.watchSlots[i]: ComplexTemplate?` — array of optional, consistent everywhere ✅
- `garmin.sendSlot(_ index: Int, template: ComplexTemplate)` — called in `SlotCard.onSend` ✅
- `SeriesRow` from `RoutineBuilderView.swift` — reused in `SlotEditorView` (same module) ✅
- `Application.Storage.getValue("slot_N")` returns `Array or Null` — handled in `SlotMenuDelegate` ✅
