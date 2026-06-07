# Technique Shot Types — Design Spec

**Date:** 2026-06-07
**Status:** Approved
**Scope:** Add 2 new shot types — "Flotteur" and "Form Shot Side to Side" — across the entire app (iPhone + Garmin watch), grouped into a new shared "Technique" stats category, and deliberately excluded from both court visualizations (Terrain tab and Hot Zones).

---

## Problem

The user practices two additional shot drills — a floater and a side-to-side form-shooting drill — that aren't tied to a fixed court position the way the existing 9 types are (free throw, 3-pointers, mid-range). They want to track these like any other exercise (pick them when starting a workout, see them in history/stats), but **not** place them on the half-court diagrams, since they don't represent a specific spot.

---

## Decisions

| Topic | Decision |
|---|---|
| Where available | Everywhere — iPhone exercise pickers AND the Garmin watch menu (sent via `Communications.transmit()` like any other type) |
| New `ExerciseType` raw values | `9` (Flotteur) and `10` (Form Shot Side to Side) — confirmed no collision with existing 0–8, and no hardcoded count/range checks exist on either the iOS or Garmin side that these would break |
| Stats grouping | Both new types share **one new category: "Technique"** (not folded into an existing category, not split into two) |
| Court placement (Terrain tab) | Deliberately **not** added to `CourtView.courtSpots` — these drills have no court position |
| Hot Zones placement (Stats tab) | Deliberately **not** added to `StatsView.HotZonesView.zones` — same reasoning |
| Display names | "Flotteur" and "Form Shot Side to Side" (user's own wording) |
| Emojis | 🪶 (Flotteur — soft, arcing floater touch) and ↔️ (Form Shot Side to Side — lateral movement) |
| Garmin watch labels | Abbreviated to fit the watch screen, matching the existing short-label convention (e.g. "Mi-dist Centre"): **"Flotteur"** and **"Form S2S"** |

---

## iOS Changes

### `Models.swift` — `ExerciseType` enum (lines 8–55)

Add two cases after `midLeft`:

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
    case floater             = 9
    case formShotSideToSide  = 10
```

Extend `name`:

```swift
        case .midLeft:      return "Mi-distance Gauche"
        case .floater:               return "Flotteur"
        case .formShotSideToSide:    return "Form Shot Side to Side"
```

Extend `emoji`:

```swift
        case .midCenter, .midRight, .midLeft:   return "🎳"
        case .floater:               return "🪶"
        case .formShotSideToSide:    return "↔️"
```

Extend `category` — both new cases get their own shared category:

```swift
        case .midCenter, .midRight, .midLeft:   return "Mi-distance"
        case .floater, .formShotSideToSide:     return "Technique"
```

No other changes to `Models.swift` are needed — `id`, `Codable`, and `CaseIterable` conformance work automatically from the raw-value cases.

### `HistoryView.swift:9` — category filter list

The category filter picker uses a hardcoded array that does **not** derive from `ExerciseType.allCases`:

```swift
private let categories = ["Lancer Franc", "3 Points", "Mi-distance"]
```

Append the new category so sessions of the new types can be filtered by it:

```swift
private let categories = ["Lancer Franc", "3 Points", "Mi-distance", "Technique"]
```

### Everything else — no changes needed

These already iterate `ExerciseType.allCases` or go through `SessionStore`'s generic per-type aggregation, so the two new types appear automatically with zero additional code:
- `WorkoutConfigView.swift:50` — exercise picker (also drives what's sent to the watch)
- `ManualSessionView.swift:111,310` — manual entry pickers
- `RoutineBuilderView.swift:145` — routine builder picker
- `SessionStore.swift:88` (`exerciseStats`) → `StatsView.swift:531` (`exerciseStatsList`) — per-exercise stats list

### `CourtView.swift` (`courtSpots`) and `StatsView.swift` (`HotZonesView.zones`)

**No changes.** Both arrays are manually curated subsets of `ExerciseType`; simply not adding entries for `.floater` / `.formShotSideToSide` keeps them off both court visualizations, exactly as requested. `SpotStats`/`spotStats(for:)` is never invoked for types absent from these arrays, so there's no dangling lookup to handle.

---

## Garmin Changes — `ExerciseMenu.mc`

### New constants (after line 17, `EX_MID_LEFT = 8`)

```javascript
const EX_FLOATER       = 9;
const EX_FORM_SHOT_S2S = 10;
```

### `getExerciseName()` (insert before the final `return "Inconnu";` on line 30)

```javascript
    if (id == EX_FLOATER)        { return "Flotteur"; }
    if (id == EX_FORM_SHOT_S2S)  { return "Form S2S"; }
```

### `ExerciseMenuView.initialize()` (append after line 45, the `Mi-dist Gauche` entry)

```javascript
        addItem(new WatchUi.MenuItem("Flotteur",  null, EX_FLOATER,       null));
        addItem(new WatchUi.MenuItem("Form S2S",  null, EX_FORM_SHOT_S2S, null));
```

The raw `exerciseId` (9 / 10) flows to the iPhone unchanged through the existing `Communications.transmit()` → `WorkoutSession.toDictionary()` → `GarminManager` → `SessionStore.add()` path, landing on `ExerciseType(rawValue: 9)` / `(rawValue: 10)` — no changes needed to that pipeline.

---

## Data Flow Summary

```
Garmin watch menu (EX_FLOATER=9 / EX_FORM_SHOT_S2S=10)
   → Communications.transmit()
   → GarminManager.handleIncomingMessage()
   → SessionStore.add()
   → ExerciseType(rawValue: 9/10) → .floater / .formShotSideToSide
   → category "Technique" → grouped in History filter & Stats per-exercise list
   → absent from CourtView.courtSpots and HotZonesView.zones (by design)
```

---

## Testing

No automated test suite exists for either the iOS app or the Garmin app in this project (confirmed: no `XCTest` targets, no Monkey C unit tests). Verification will be:
- **iOS:** build succeeds (`xcodebuild`), the two new types appear in exercise pickers (Workout Config, Manual Entry, Routine Builder), in History's category filter ("Technique"), and in Stats' per-exercise list — and do **not** appear on the Terrain court or in Hot Zones.
- **Garmin:** build succeeds, the two new menu entries appear in the exercise menu and a tracked session for each transmits correctly to the iPhone with the right `exerciseId`/name.

---

## Out of Scope

- No changes to `CourtView` or `HotZonesView` rendering logic — they simply continue iterating their existing curated arrays.
- No changes to the watch-side tracking/summary screens (`WorkoutView.mc`, `SummaryView.mc`) — they're already generic over `exerciseId`.
- No changes to `Communications.transmit()` / `toDictionary()` — the data shape is unchanged, only the `exerciseId` range grows.
