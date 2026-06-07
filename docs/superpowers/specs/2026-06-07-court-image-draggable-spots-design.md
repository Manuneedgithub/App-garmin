# Court Image + Draggable Spot Positions — Design Spec

**Date:** 2026-06-07
**Status:** Approved
**Scope:** Replace the programmatically-drawn half-court in `CourtView` with a real court photo, and let the user drag the stat spots to align them with that photo's markings — with the adjusted positions saved permanently.

---

## Problem

`CourtView` currently draws the half-court itself (`Canvas` + `Path`s tuned to an approximate diagram). The user supplied a real court photo they'd rather use as the background. Because a photo's proportions and marking positions won't exactly match the hand-tuned `nx`/`ny` constants in `courtSpots`, the 9 stat spots need to be repositionable so the user can align them with the photo's actual lines — once, by hand — and have that stick.

---

## Decisions

| Topic | Decision |
|---|---|
| Court rendering | Replace `courtShape()` Canvas with the supplied photo (`Image`, asset catalog) |
| Image fitting | `aspectRatio(contentMode: .fit)`, centered — never stretched (same lesson as the recent court-proportion fix) |
| Spot alignment | Spots positioned relative to the image's actual displayed rect, not the raw canvas |
| Repositioning trigger | Explicit "Modifier" edit-mode toggle in the toolbar (not long-press) — keeps tap-to-view-stats unambiguous |
| Persistence | Custom positions saved permanently via the existing `UserDefaults`/`Codable` pattern (survive relaunch) |
| Defaults | `courtSpots` constants remain the fallback/starting layout; overrides layer on top per `ExerciseType` |
| Reset | "Réinitialiser" button (edit mode only) clears all overrides, behind a confirmation alert |

---

## Data Model Changes

### New: `SpotPosition` — `Models.swift`

```swift
struct SpotPosition: Codable {
    var nx: CGFloat
    var ny: CGFloat
}
```

Plain normalized-coordinate pair (same `nx`/`ny` convention already used by `courtSpots`: fraction of the court rect from the left / from the bottom).

### Modified: `SessionStore`

```swift
@Published private(set) var spotPositionOverrides: [ExerciseType: SpotPosition] = [:]

func setSpotPosition(_ type: ExerciseType, nx: CGFloat, ny: CGFloat)
func resetSpotPositions()
```

- Persisted to `UserDefaults` as JSON under a new key (`basket_spot_positions`), following the exact same `save()`/`load()` pattern as `templates`/`watchSlots`.
- `setSpotPosition` upserts one entry and saves; `resetSpotPositions` empties the dictionary and saves.
- On-disk shape is `[Int: SpotPosition]` keyed by `ExerciseType.rawValue` — `Dictionary` only encodes to a clean JSON object when its key is `Int` or `String`, and there's no existing precedent in this codebase for persisting enum-keyed maps. `save()`/`load()` convert between that wire format and the in-memory `[ExerciseType: SpotPosition]`, skipping any raw value that no longer maps to a known `ExerciseType` (same "tolerate unknown data" spirit as the rest of `SessionStore`'s decoding).

---

## View Changes

### `CourtView.swift`

**Court background**
- `courtShape()` is removed. In its place: `Image("CourtDiagram").resizable().aspectRatio(contentMode: .fit)`.
- A `courtRect(in:)` helper (parallel to the one just added for the drawn court) computes the image's centered, aspect-correct displayed rect from `UIImage(named: "CourtDiagram")?.size`, given the `GeometryReader` size. Spots are positioned with `rect.minX + nx * rect.width` / `rect.minY + (1 - ny) * rect.height`, exactly as today — only the rect's source changes (image aspect ratio vs. hardcoded court-proportion constant).

**Resolved spot position**
- A small helper resolves each spot's working position: `store.spotPositionOverrides[type] ?? SpotPosition(nx: defaultNx, ny: defaultNy)` where the defaults come from the existing `courtSpots` array.

**Edit mode**
- New `@State private var isEditing = false`.
- Toolbar gains a "Modifier" / "Terminé" button that toggles `isEditing`.
- While `isEditing == false` (current behavior): spots are `NavigationLink`s to `SpotDetailView`, colored by stats, showing %.
- While `isEditing == true`:
  - Spots are plain views (no `NavigationLink` — tapping does nothing but drag) with a dashed ring overlay signaling they're movable.
  - Each spot carries a `DragGesture(minimumDistance: 0)`:
    - `.onChanged`: track a live offset in local `@State` (e.g. `@State private var dragOffsets: [ExerciseType: CGSize]`) so the spot visually follows the finger.
    - `.onEnded`: compute the spot's final absolute position (original position + total translation), convert back to normalized coordinates relative to `rect` (`nx = (finalX - rect.minX) / rect.width`, `ny = 1 - (finalY - rect.minY) / rect.height`), clamp both to `0...1`, call `store.setSpotPosition(type, nx:, ny:)`, and clear that spot's entry from `dragOffsets`.
  - A "Réinitialiser" toolbar button appears (only in edit mode), opens a confirmation `.alert`, and on confirm calls `store.resetSpotPositions()`.

**Legend**
- Unchanged; remains visible in both modes (it doesn't conflict with the new toolbar buttons — `Modifier`/`Terminé` and `Réinitialiser` go in `.topBarLeading`, the legend stays `.topBarTrailing`).

---

## Data Flow

```
First launch / no overrides
  CourtView reads courtSpots defaults → spots render at hardcoded nx/ny

User taps "Modifier"
  isEditing = true → spots become draggable, lose NavigationLink

User drags a spot
  DragGesture.onChanged → live visual offset (local @State, not persisted)
  DragGesture.onEnded   → normalized nx/ny computed against image rect
                        → store.setSpotPosition(type, nx, ny)
                        → SessionStore persists to UserDefaults (basket_spot_positions)
                        → @Published triggers re-render at the new resolved position

User taps "Terminé"
  isEditing = false → spots become NavigationLinks again, normal tap-to-detail

User taps "Réinitialiser" → confirms
  store.resetSpotPositions() → overrides dict emptied + persisted
  → all spots snap back to courtSpots defaults
```

---

## Files Modified / Created

| File | Change |
|---|---|
| `ios-app/.../Assets.xcassets/CourtDiagram.imageset` | **New** — the supplied court photo |
| `ios-app/.../Models/Models.swift` | Add `SpotPosition` |
| `ios-app/.../Models/SessionStore.swift` | Add `spotPositionOverrides`, `setSpotPosition`, `resetSpotPositions`, persistence plumbing |
| `ios-app/.../Views/CourtView.swift` | Replace drawn court with image; add edit mode, drag gesture, reset button |

---

## Error / Edge Cases

| Scenario | Behavior |
|---|---|
| Drag ends outside the image rect | Normalized `nx`/`ny` clamped to `0...1` — spot can't be placed off the court image |
| Image asset missing/fails to load | `Image("CourtDiagram")` renders as a blank placeholder; spots still position against a `0`-sized rect fallback (degrades gracefully, matches SwiftUI's default `Image` behavior — no crash) |
| Override exists for a since-removed/renamed `ExerciseType` | Skipped on decode (unknown raw value) — doesn't block loading the rest of the dictionary |
| User exits edit mode mid-drag | Not reachable in this design — toolbar buttons are the only mode exit, and a drag holds focus until `.onEnded` fires |
| Reset tapped with no overrides | `resetSpotPositions()` is a no-op write (empty dict → empty dict); harmless |

---

## Out of Scope

- Editing/replacing the court image from within the app (it's a bundled asset)
- Per-user or per-device position profiles (single global override set)
- Undo/redo for individual drags (only full reset)
- Animating the snap-back on reset
