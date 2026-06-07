# Technique Shot Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new shot types — "Flotteur" and "Form Shot Side to Side" — across the iPhone app and the Garmin watch, grouped under a new shared "Technique" stats category, while keeping them off both court visualizations (Terrain tab and Hot Zones).

**Architecture:** Two new `ExerciseType` cases (raw values 9 and 10) ride the existing generic plumbing — `CaseIterable` pickers, `SessionStore`'s per-type stats aggregation, and the `Communications.transmit()` → `toDictionary()` → `GarminManager` → `SessionStore.add()` pipeline — with zero structural changes. The watch gains two mirrored menu constants/entries. The only non-generic touch point is `HistoryView`'s hardcoded category filter list, which needs the new category appended by hand.

**Tech Stack:** Swift 5 / SwiftUI (iOS 16+), Monkey C / Connect IQ SDK 9.1.0 (Garmin). No external dependencies, no test target on either side (this project has none — iOS verification is via `xcodebuild`; Garmin verification is via the Windows-side Monkey C build/simulator per `CLAUDE.md`, not available on this Mac).

**Spec:** `docs/superpowers/specs/2026-06-07-technique-shot-types-design.md`

---

## Task 1: iOS — `ExerciseType` enum + History category filter

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift:8-55`
- Modify: `ios-app/BasketTrainer/Views/HistoryView.swift:9`

### Context

`ExerciseType` is an `Int, CaseIterable, Codable, Identifiable` enum. Every iOS picker (`WorkoutConfigView`, `ManualSessionView`, `RoutineBuilderView`) and the stats list (`SessionStore.exerciseStats` → `StatsView.exerciseStatsList`) iterate `ExerciseType.allCases` generically — adding cases here is sufficient to surface them everywhere except one spot: `HistoryView` keeps its own hardcoded list of category names for its filter picker, which must be updated by hand.

`CourtView.courtSpots` and `StatsView.HotZonesView.zones` are separate, manually curated arrays of specific `ExerciseType` cases — per the spec, we deliberately do **not** add entries there, so no change is needed in either file.

- [ ] **Step 1: Add the two new enum cases**

In `ios-app/BasketTrainer/Models/Models.swift`, the enum currently starts:

```swift
enum ExerciseType: Int, CaseIterable, Codable, Identifiable {
    case freethrow      = 0
    case threeCenter    = 1
    case threeRight45   = 2
    case threeLeft45    = 3
    case threeCornerR   = 4
    case threeCornerL   = 5
    case midCenter      = 6
    case midRight       = 7
    case midLeft        = 8

    var id: Int { rawValue }
```

Add two cases right after `midLeft`:

```swift
enum ExerciseType: Int, CaseIterable, Codable, Identifiable {
    case freethrow      = 0
    case threeCenter    = 1
    case threeRight45   = 2
    case threeLeft45    = 3
    case threeCornerR   = 4
    case threeCornerL   = 5
    case midCenter      = 6
    case midRight       = 7
    case midLeft        = 8
    case floater              = 9
    case formShotSideToSide   = 10

    var id: Int { rawValue }
```

- [ ] **Step 2: Extend the `name` switch**

The `name` computed property currently ends:

```swift
        case .midCenter:    return "Mi-distance Centre"
        case .midRight:     return "Mi-distance Droite"
        case .midLeft:      return "Mi-distance Gauche"
        }
    }
```

Add the two new cases before the closing brace:

```swift
        case .midCenter:    return "Mi-distance Centre"
        case .midRight:     return "Mi-distance Droite"
        case .midLeft:      return "Mi-distance Gauche"
        case .floater:              return "Flotteur"
        case .formShotSideToSide:   return "Form Shot Side to Side"
        }
    }
```

- [ ] **Step 3: Extend the `emoji` switch**

The `emoji` computed property currently reads:

```swift
    var emoji: String {
        switch self {
        case .freethrow:                        return "🎯"
        case .threeCenter:                      return "🏀"
        case .threeRight45, .threeLeft45:       return "↗️"
        case .threeCornerR, .threeCornerL:      return "📐"
        case .midCenter, .midRight, .midLeft:   return "🎳"
        }
    }
```

Add a line for the two new cases before the closing brace:

```swift
    var emoji: String {
        switch self {
        case .freethrow:                        return "🎯"
        case .threeCenter:                      return "🏀"
        case .threeRight45, .threeLeft45:       return "↗️"
        case .threeCornerR, .threeCornerL:      return "📐"
        case .midCenter, .midRight, .midLeft:   return "🎳"
        case .floater:                          return "🪶"
        case .formShotSideToSide:               return "↔️"
        }
    }
```

- [ ] **Step 4: Extend the `category` switch**

The `category` computed property currently reads:

```swift
    // Catégorie pour regrouper dans les stats
    var category: String {
        switch self {
        case .freethrow:                        return "Lancer Franc"
        case .threeCenter, .threeRight45,
             .threeLeft45, .threeCornerR,
             .threeCornerL:                     return "3 Points"
        case .midCenter, .midRight, .midLeft:   return "Mi-distance"
        }
    }
```

Add a `"Technique"` case grouping both new types before the closing brace:

```swift
    // Catégorie pour regrouper dans les stats
    var category: String {
        switch self {
        case .freethrow:                        return "Lancer Franc"
        case .threeCenter, .threeRight45,
             .threeLeft45, .threeCornerR,
             .threeCornerL:                     return "3 Points"
        case .midCenter, .midRight, .midLeft:   return "Mi-distance"
        case .floater, .formShotSideToSide:     return "Technique"
        }
    }
```

- [ ] **Step 5: Add "Technique" to `HistoryView`'s category filter list**

In `ios-app/BasketTrainer/Views/HistoryView.swift`, line 9 currently reads:

```swift
    private let categories = ["Lancer Franc", "3 Points", "Mi-distance"]
```

Change it to:

```swift
    private let categories = ["Lancer Franc", "3 Points", "Mi-distance", "Technique"]
```

- [ ] **Step 6: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift ios-app/BasketTrainer/Views/HistoryView.swift
git commit -m "feat(ios): add Flotteur and Form Shot Side to Side exercise types"
```

---

## Task 2: Garmin — `ExerciseMenu.mc` mirror

**Files:**
- Modify: `garmin-app/source/ExerciseMenu.mc`

### Context

`ExerciseMenu.mc` (87 lines) hand-mirrors `ExerciseType` on the watch: `EX_*` integer constants matching the iOS raw values, `getExerciseName(id)` for display, and `ExerciseMenuView.initialize()` which builds the scrollable `Menu2` the user picks an exercise from. The chosen `exerciseId` (a raw `Number`) flows untouched through `Communications.transmit()` → `toDictionary()` → `GarminManager` → `SessionStore.add()` on the iPhone side, where `ExerciseType(rawValue:)` reconstructs the case — so the new constants must use raw values **9** and **10** to match the iOS enum exactly (Task 1).

There is no Monkey C build tooling on this Mac (per `CLAUDE.md`, Garmin builds happen on Windows via the VS Code "Monkey C: Build for Device" command and the PowerShell simulator scripts) — this task ends at commit; building/testing on the watch happens separately on Windows.

- [ ] **Step 1: Add the two new `EX_*` constants**

Lines 9–17 currently read:

```javascript
const EX_FREETHROW       = 0;
const EX_THREE_CENTER    = 1;
const EX_THREE_RIGHT_45  = 2;
const EX_THREE_LEFT_45   = 3;
const EX_THREE_CORNER_R  = 4;
const EX_THREE_CORNER_L  = 5;
const EX_MID_CENTER      = 6;
const EX_MID_RIGHT       = 7;
const EX_MID_LEFT        = 8;
```

Add two more constants after `EX_MID_LEFT`:

```javascript
const EX_FREETHROW       = 0;
const EX_THREE_CENTER    = 1;
const EX_THREE_RIGHT_45  = 2;
const EX_THREE_LEFT_45   = 3;
const EX_THREE_CORNER_R  = 4;
const EX_THREE_CORNER_L  = 5;
const EX_MID_CENTER      = 6;
const EX_MID_RIGHT       = 7;
const EX_MID_LEFT        = 8;
const EX_FLOATER         = 9;
const EX_FORM_SHOT_S2S   = 10;
```

- [ ] **Step 2: Add the two new cases to `getExerciseName()`**

The function currently reads (lines 20–31):

```javascript
function getExerciseName(id as Number) as String {
    if (id == EX_FREETHROW)      { return "Lancer Franc"; }
    if (id == EX_THREE_CENTER)   { return "3pts Centre"; }
    if (id == EX_THREE_RIGHT_45) { return "3pts 45 Dr."; }
    if (id == EX_THREE_LEFT_45)  { return "3pts 45 Ga."; }
    if (id == EX_THREE_CORNER_R) { return "3pts Coin Dr."; }
    if (id == EX_THREE_CORNER_L) { return "3pts Coin Ga."; }
    if (id == EX_MID_CENTER)     { return "Mi-dist Centre"; }
    if (id == EX_MID_RIGHT)      { return "Mi-dist Droite"; }
    if (id == EX_MID_LEFT)       { return "Mi-dist Gauche"; }
    return "Inconnu";
}
```

Insert two more checks before the final `return "Inconnu";`:

```javascript
function getExerciseName(id as Number) as String {
    if (id == EX_FREETHROW)      { return "Lancer Franc"; }
    if (id == EX_THREE_CENTER)   { return "3pts Centre"; }
    if (id == EX_THREE_RIGHT_45) { return "3pts 45 Dr."; }
    if (id == EX_THREE_LEFT_45)  { return "3pts 45 Ga."; }
    if (id == EX_THREE_CORNER_R) { return "3pts Coin Dr."; }
    if (id == EX_THREE_CORNER_L) { return "3pts Coin Ga."; }
    if (id == EX_MID_CENTER)     { return "Mi-dist Centre"; }
    if (id == EX_MID_RIGHT)      { return "Mi-dist Droite"; }
    if (id == EX_MID_LEFT)       { return "Mi-dist Gauche"; }
    if (id == EX_FLOATER)        { return "Flotteur"; }
    if (id == EX_FORM_SHOT_S2S)  { return "Form S2S"; }
    return "Inconnu";
}
```

- [ ] **Step 3: Add two `MenuItem` entries to `ExerciseMenuView.initialize()`**

The method currently reads (lines 35–46):

```javascript
    function initialize() {
        Menu2.initialize({:title => "Exercice"});
        addItem(new WatchUi.MenuItem("Lancer Franc",   null, EX_FREETHROW,      null));
        addItem(new WatchUi.MenuItem("3pts Centre",    null, EX_THREE_CENTER,   null));
        addItem(new WatchUi.MenuItem("3pts 45 Dr.",    null, EX_THREE_RIGHT_45, null));
        addItem(new WatchUi.MenuItem("3pts 45 Ga.",    null, EX_THREE_LEFT_45,  null));
        addItem(new WatchUi.MenuItem("3pts Coin Dr.",  null, EX_THREE_CORNER_R, null));
        addItem(new WatchUi.MenuItem("3pts Coin Ga.",  null, EX_THREE_CORNER_L, null));
        addItem(new WatchUi.MenuItem("Mi-dist Centre", null, EX_MID_CENTER,     null));
        addItem(new WatchUi.MenuItem("Mi-dist Droite", null, EX_MID_RIGHT,      null));
        addItem(new WatchUi.MenuItem("Mi-dist Gauche", null, EX_MID_LEFT,       null));
    }
```

Add two more `addItem` calls before the closing brace:

```javascript
    function initialize() {
        Menu2.initialize({:title => "Exercice"});
        addItem(new WatchUi.MenuItem("Lancer Franc",   null, EX_FREETHROW,      null));
        addItem(new WatchUi.MenuItem("3pts Centre",    null, EX_THREE_CENTER,   null));
        addItem(new WatchUi.MenuItem("3pts 45 Dr.",    null, EX_THREE_RIGHT_45, null));
        addItem(new WatchUi.MenuItem("3pts 45 Ga.",    null, EX_THREE_LEFT_45,  null));
        addItem(new WatchUi.MenuItem("3pts Coin Dr.",  null, EX_THREE_CORNER_R, null));
        addItem(new WatchUi.MenuItem("3pts Coin Ga.",  null, EX_THREE_CORNER_L, null));
        addItem(new WatchUi.MenuItem("Mi-dist Centre", null, EX_MID_CENTER,     null));
        addItem(new WatchUi.MenuItem("Mi-dist Droite", null, EX_MID_RIGHT,      null));
        addItem(new WatchUi.MenuItem("Mi-dist Gauche", null, EX_MID_LEFT,       null));
        addItem(new WatchUi.MenuItem("Flotteur",       null, EX_FLOATER,        null));
        addItem(new WatchUi.MenuItem("Form S2S",       null, EX_FORM_SHOT_S2S,  null));
    }
```

- [ ] **Step 4: Commit**

```bash
git add garmin-app/source/ExerciseMenu.mc
git commit -m "feat(garmin): add Flotteur and Form S2S to exercise menu"
```

---

## Manual Verification (post-implementation, on the appropriate machine)

These checks can't be automated (no test target on either side) and should be done where each platform actually runs:

**iOS (this Mac, simulator):**
- Launch the app, open the exercise picker in Workout Config / Manual Entry / Routine Builder — confirm "Flotteur" 🪶 and "Form Shot Side to Side" ↔️ appear at the end of the list.
- In History, open the category filter — confirm "Technique" is selectable and filters to sessions of either new type.
- In Stats, confirm both new types appear in the per-exercise stats list.
- In the Terrain tab and in Stats → Hot Zones, confirm neither new type appears (they have no court spot).

**Garmin (Windows, per `CLAUDE.md` build/simulator instructions):**
- Build for device, open the exercise menu, confirm "Flotteur" and "Form S2S" appear at the end of the list and are selectable.
- Track a short session of each, confirm it transmits to the iPhone and lands as the correct type with the correct name.
