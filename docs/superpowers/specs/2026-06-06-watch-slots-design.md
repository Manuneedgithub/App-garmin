# Watch Slots — Design Spec

**Date:** 2026-06-06
**Status:** Approved
**Scope:** Replace the ephemeral "pending routine" system with 5 persistent, named training slots configurable from the iPhone and stored on the watch.

---

## Problem

The current "Objectif complexe" flow requires the iPhone to push a routine to the watch right before each session. If the watch restarts or the routine was already consumed, it's gone. The user has to reach for the phone before every training session, which is impractical on the court.

---

## Decisions

| Topic | Decision |
|---|---|
| Number of slots | 5 fixed slots — always visible on watch |
| Slot names | Fixed: "Entraînement 1" to "Entraînement 5" |
| Watch persistence | `Application.Storage` — survives watch restarts |
| Empty slot behaviour | Shown but non-selectable (greyed label) |
| iPhone storage | `[ComplexTemplate?]` array of 5, persisted in UserDefaults |
| Message protocol | `{"type": "slot", "index": 0–4, "series": [...]}` |
| Removed | `RoutineWaitView`, `RoutineWaitDelegate`, `_pendingRoutine` in `BasketApp.mc` |
| Reused | `RoutineRunner`, `RoutineStartView/Delegate`, `RoutineSeriesDoneView/Delegate`, `RoutineFinalView/Delegate` |

---

## Garmin Changes

### Modified: `BasketApp.mc`

Remove `_pendingRoutine as Dictionary or Null` and associated methods (`getPendingRoutine`, `clearPendingRoutine`).

`onMessage` now handles `type == "slot"`:
```monkey-c
if (dict["type"].equals("routine")) { /* remove */ }
if (dict["type"].equals("slot")) {
    var index  = dict["index"] as Number;   // 0–4
    var series = dict["series"] as Array;
    Application.Storage.setValue("slot_" + index.toString(), series);
}
```

### New: `SlotMenu.mc`

`SlotMenuView extends WatchUi.Menu2` — always shows 5 items regardless of storage state:

```monkey-c
class SlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Entraînements"});
        for (var i = 0; i < 5; i++) {
            var series = Application.Storage.getValue("slot_" + i.toString());
            var label  = "Entraînement " + (i + 1).toString();
            var sub    = (series != null) ? seriesSummary(series) : "(vide)";
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}
```

`seriesSummary(series)` returns a short string like "3 séries · 35 tirs".

`SlotMenuDelegate extends WatchUi.Menu2InputDelegate` — `onSelect` reads the slot from `Application.Storage` and either launches `RoutineStartView` (if configured) or shows a `SlotEmptyView` (simple read-only screen saying "Configure depuis l'iPhone").

### Modified: `MainMenu.mc`

Rename menu item id=2 from "Objectif complexe" to "Entraînements". Wire to `SlotMenuView / SlotMenuDelegate` instead of `RoutineWaitView`.

Remove `RoutineWaitView` and `RoutineWaitDelegate` classes (no longer needed).

---

## iPhone Changes

### Modified: `SessionStore.swift`

Add storage for 5 watch slots:
```swift
@Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: 5)
private let slotsKey = "basket_watch_slots"

func setWatchSlot(_ index: Int, template: ComplexTemplate?) { ... }  // saves to UserDefaults
func loadSlots() { ... }   // called in init()
```

### Modified: `GarminManager.swift`

Add:
```swift
func sendSlot(_ index: Int, template: ComplexTemplate) {
    guard let device = connectedDevice else { return }
    let app = IQApp(uuid: appUUID, store: appUUID, device: device)
    let payload: [String: Any] = [
        "type": "slot",
        "index": index,
        "series": template.series.map {
            ["exerciseId": $0.exerciseType.rawValue,
             "totalShots": $0.totalShots,
             "shotTypeId": $0.shotType.rawValue]
        }
    ]
    sdk.sendMessage(payload, to: app, progress: nil) { _ in }
}
```

Remove `sendRoutine(_:)` and `startGuidedSession` / `cancelGuidedSession` / `guidedTemplate` / `guidedIndex` / `guidedSeries`. Each series transmitted by the watch is now stored as an individual simple `WorkoutSession` in history (the `else` branch of `handleSessionOrGuided` already does this). The `handleSessionOrGuided` method can be simplified to always call `store.add(session)` directly.

### New: `SlotsView.swift`

Accessible from `HomeView` via a "Configurer la montre" button (or toolbar item).

Shows 5 slot cards vertically:
- Header: "Entraînement N" + count of series if configured
- Body: list of series (exercise + shots + shot type) if configured, "(vide)" if not
- Footer: "Modifier" button → opens slot editor sheet | "Envoyer à la montre ▶" button (orange, disabled if no device connected)

Slot editor = `RoutineBuilderView` adapted with:
- No name field (name is fixed)
- "Sauvegarder" saves to `store.setWatchSlot(index, template)` and dismisses
- No template save option

### Modified: `ContentView.swift` / `HomeView.swift`

Add a "Configurer la montre" button in `HomeView` that presents `SlotsView` as a sheet.

### Modified: `project.pbxproj`

Register `SlotsView.swift` (2 new file IDs).

---

## Data Flow

```
iPhone SlotsView
  → user edits slot N content (series + shot types)
  → store.setWatchSlot(N, template)     // persists on iPhone
  → garmin.sendSlot(N, template)        // BLE push

Watch BasketApp.onMessage
  → type=="slot" → Application.Storage.setValue("slot_N", series)

Watch SlotMenuView
  → reads Application.Storage on initialize()
  → shows "Entraînement N · X séries" or "(vide)"

Watch SlotMenuDelegate.onSelect
  → reads slot from storage → RoutineRunner(slot) → RoutineStartView

Watch WorkoutSession.toDictionary()
  → includes shotTypeId
  → Communications.transmit() → GarminManager.parseAndStore()
  → SessionStore.add()
```

---

## Files Modified / Created

| File | Change |
|---|---|
| `garmin-app/source/BasketApp.mc` | Remove pending routine, add slot storage in onMessage |
| `garmin-app/source/MainMenu.mc` | Rename item, wire to SlotMenu, remove RoutineWait classes |
| `garmin-app/source/RoutineRunner.mc` | Remove RoutineWaitView/Delegate (moved or deleted) |
| `garmin-app/source/SlotMenu.mc` | **New** — SlotMenuView + SlotMenuDelegate + SlotEmptyView |
| `ios-app/.../Models/SessionStore.swift` | Add watchSlots storage |
| `ios-app/.../Managers/GarminManager.swift` | Replace sendRoutine with sendSlot, remove guided tracking |
| `ios-app/.../Views/SlotsView.swift` | **New** — 5 slot cards + editor |
| `ios-app/.../Views/HomeView.swift` | Add "Configurer la montre" button |
| `ios-app/BasketTrainer.xcodeproj/project.pbxproj` | Register SlotsView.swift |

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Slot empty on watch | Shown as "(vide)", tap → `SlotEmptyView` with instruction message |
| Watch not connected | "Envoyer" button disabled on iPhone |
| Watch restarts | Slots survive (Application.Storage is persistent) |
| iPhone reinstall | Slots lost on iPhone side — user re-configures and re-sends |
| Slot overwritten | Last write wins — no confirmation needed |
