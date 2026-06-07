# Court Image + Draggable Spot Positions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the programmatically-drawn half-court in the "Terrain" tab with the user's real court photo, and let the user drag the 9 stat spots to align them with that photo's markings — with the adjusted positions saved permanently.

**Architecture:** `CourtView` swaps its `Canvas`-drawn `courtShape()` for an `Image("CourtDiagram")` rendered through the same aspect-locked, centered-rect approach as the existing court-proportion fix (only the aspect ratio's source changes — from a hardcoded constant to the photo's own pixel dimensions). A new `SpotPosition` model and `SessionStore.spotPositionOverrides` dictionary (persisted to `UserDefaults` exactly like `templates`/`watchSlots`) store per-`ExerciseType` position overrides that layer on top of the existing `courtSpots` defaults. An edit-mode toggle in the toolbar switches spots between `NavigationLink`s (normal browsing) and draggable circles (`DragGesture`) that write back normalized `nx`/`ny` coordinates on release.

**Tech Stack:** Swift 5 / SwiftUI (iOS 16+), `UIImage`/asset catalog, `DragGesture`, `UserDefaults`/`Codable` (existing `SessionStore` persistence pattern). No external dependencies, no test target (this project has none — verification is via `xcodebuild` + simulator).

---

## File Map

| File | Action |
|---|---|
| `ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/` | **Create** — court photo asset (`garmin-app/Image.jpg`, 663×619) |
| `ios-app/BasketTrainer/Models/Models.swift` | Modify — add `SpotPosition` |
| `ios-app/BasketTrainer/Models/SessionStore.swift` | Modify — add `spotPositionOverrides`, `setSpotPosition`, `resetSpotPositions`, persistence |
| `ios-app/BasketTrainer/Views/CourtView.swift` | Modify — replace drawn court with image, add edit mode + drag + reset |

No `project.pbxproj` changes are needed: asset catalogs are folder references (Xcode already has `Assets.xcassets` registered; new imagesets inside it are picked up automatically — see `AppIcon.appiconset` / `AccentColor.colorset` for precedent), and no new Swift files are being created.

---

## Task 1: Court photo asset

**Files:**
- Create: `ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/Contents.json`
- Create: `ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/CourtDiagram.jpg`

### Context

The user placed their court photo at `garmin-app/Image.jpg` (JPEG, 663×619px, RGB). It needs to become an asset-catalog image named `CourtDiagram` so `Image("CourtDiagram")` and `UIImage(named: "CourtDiagram")` can find it. Single-image, single-scale imagesets (one file, empty `2x`/`3x` slots) are standard Xcode output — this mirrors the structure Xcode itself generates when you drag one image into a catalog.

- [ ] **Step 1: Create the imageset directory and copy the photo into it**

```bash
mkdir -p "ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset"
cp "garmin-app/Image.jpg" "ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/CourtDiagram.jpg"
```

- [ ] **Step 2: Write `Contents.json` for the imageset**

Create `ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "CourtDiagram.jpg",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Verify the file landed correctly**

```bash
ls -la "ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/"
```

Expected: both `Contents.json` and `CourtDiagram.jpg` are listed.

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Assets.xcassets/CourtDiagram.imageset/
git commit -m "feat(ios): add court photo asset for Terrain tab background"
```

---

## Task 2: `SpotPosition` model

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift:326-335`

### Context

`SpotPosition` is a plain normalized-coordinate pair — same `nx`/`ny` convention already used by the private `CourtSpot` in `CourtView.swift` (fraction of the court rect from the left / from the bottom). It needs `Codable` so `SessionStore` can persist it to `UserDefaults` as JSON, matching every other persisted model in this file (`WorkoutSession`, `ComplexTemplate`, etc.). `CGFloat` is usable here with only `import Foundation` already present — no new import needed (verified: `Codable` structs with `CGFloat` fields compile fine under `import Foundation` alone).

- [ ] **Step 1: Append `SpotPosition` after `SpotStats`**

`SpotStats` is the last struct in `Models.swift` (ends at line 334). Add this immediately after its closing brace:

```swift

// ─────────────────────────────────────────────────
// Position personnalisée d'un repère sur le terrain
// (coordonnées normalisées, même convention que CourtSpot :
// nx/ny = fraction du rectangle du terrain depuis bas-gauche)
// ─────────────────────────────────────────────────
struct SpotPosition: Codable {
    var nx: CGFloat
    var ny: CGFloat
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift
git commit -m "feat(ios): add SpotPosition model for custom court spot placement"
```

---

## Task 3: `SessionStore` — persist spot position overrides

**Files:**
- Modify: `ios-app/BasketTrainer/Models/SessionStore.swift`

### Context

This follows the *exact* same shape as the existing `watchSlots` persistence (`@Published` dict/array → `setX`/`saveX`/`loadX`, JSON in `UserDefaults` under a dedicated key, called from `init()`). The one wrinkle: `Dictionary` only encodes to a clean JSON object when its key is `Int` or `String` — `[ExerciseType: SpotPosition]` won't round-trip through `JSONEncoder` directly. So the on-disk wire format is `[Int: SpotPosition]` keyed by `ExerciseType.rawValue`; `save`/`load` convert between that and the in-memory `[ExerciseType: SpotPosition]`, silently skipping any raw value that no longer maps to a known `ExerciseType` (same "tolerate unknown data" spirit as `loadSlots`/`loadTemplates`).

- [ ] **Step 1: Add the published property and storage key**

In `SessionStore.swift:12-14`, add a new `@Published` line after `watchSlots`:

```swift
    @Published private(set) var sessions:   [WorkoutSession]   = []
    @Published private(set) var templates:  [ComplexTemplate]  = []
    @Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: maxWatchSlots)
    @Published private(set) var spotPositionOverrides: [ExerciseType: SpotPosition] = [:]
```

And in `SessionStore.swift:16-18`, add a new key constant after `slotsKey`:

```swift
    private let storageKey   = "basket_sessions"
    private let templateKey  = "basket_templates"
    private let slotsKey     = "basket_watch_slots"
    private let spotPositionsKey = "basket_spot_positions"
```

- [ ] **Step 2: Load overrides on init**

In `SessionStore.swift:23-27`, add a call to the new loader:

```swift
    init() {
        load()
        loadTemplates()
        loadSlots()
        loadSpotPositions()
    }
```

- [ ] **Step 3: Add `setSpotPosition` and `resetSpotPositions`**

Add a new section after `// ── Watch Slots ──` (`SessionStore.swift:152-158`, right after `setWatchSlot`):

```swift
    // ── Spot Positions ──

    func setSpotPosition(_ type: ExerciseType, nx: CGFloat, ny: CGFloat) {
        spotPositionOverrides[type] = SpotPosition(nx: nx, ny: ny)
        saveSpotPositions()
    }

    func resetSpotPositions() {
        spotPositionOverrides = [:]
        saveSpotPositions()
    }
```

- [ ] **Step 4: Add `saveSpotPositions`/`loadSpotPositions` (wire-format conversion)**

Add these alongside `saveSlots`/`loadSlots` (right after `loadSlots`, `SessionStore.swift:166-172`):

```swift
    private func saveSpotPositions() {
        let wire = Dictionary(uniqueKeysWithValues:
            spotPositionOverrides.map { (key, value) in (key.rawValue, value) })
        if let data = try? JSONEncoder().encode(wire) {
            UserDefaults.standard.set(data, forKey: spotPositionsKey)
        }
    }

    private func loadSpotPositions() {
        guard let data = UserDefaults.standard.data(forKey: spotPositionsKey),
              let decoded = try? JSONDecoder().decode([Int: SpotPosition].self, from: data)
        else { return }
        var result: [ExerciseType: SpotPosition] = [:]
        for (rawValue, position) in decoded {
            if let type = ExerciseType(rawValue: rawValue) {
                result[type] = position
            }
        }
        spotPositionOverrides = result
    }
```

- [ ] **Step 5: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ios-app/BasketTrainer/Models/SessionStore.swift
git commit -m "feat(ios): persist custom court spot positions in SessionStore"
```

---

## Task 4: `CourtView` — image background, edit mode, drag, reset

**Files:**
- Modify: `ios-app/BasketTrainer/Views/CourtView.swift` (full rewrite of the file's content — same `courtSpots` data, new rendering/interaction)

### Context

This replaces `courtShape()` (the `Canvas`-drawn court) with `Image("CourtDiagram")`, displayed through the same aspect-locked-and-centered `courtRect(in:)` pattern that fixed the stretching bug — except the aspect ratio now comes from the photo's own pixel size (`UIImage(named:)?.size`) rather than the hardcoded `15.0/14.0` constant, since the spots must align with *this* image's printed lines, not an idealized court.

Three new pieces of state drive the editing flow:
- `isEditing` — toggled by the toolbar's "Modifier"/"Terminé" button; switches each spot between a `NavigationLink` (normal tap-to-detail) and a draggable circle with a dashed ring
- `dragOffsets` — a live, per-spot visual offset updated on every `DragGesture.onChanged`, so the spot tracks the finger; cleared on `.onEnded`
- `showResetConfirmation` — drives the `.alert` for the "Réinitialiser" button (edit mode only), which on confirmation calls `store.resetSpotPositions()`

`UIImage` requires `import UIKit` (this file currently only has `import SwiftUI`; no other file in the project imports `UIKit` yet, so this is a new but necessary addition — confirmed `UIImage` isn't available transitively through `SwiftUI` alone).

- [ ] **Step 1: Replace the entire contents of `CourtView.swift`**

```swift
import SwiftUI
import UIKit

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat
    let ny: CGFloat
}

// Default layout — used whenever no override exists yet (first launch, or
// any spot the user hasn't repositioned). ny = fraction of the court rect
// from the bottom (0=bottom edge, 1=top edge); mapping: cy = rect.minY
// + (1 - ny) * rect.height. The rect — not the raw canvas — is what's
// proportioned like the photo, so spots line up with its markings
// regardless of the screen's aspect ratio. Drag-and-reposition (below)
// lets the user correct any spot that doesn't quite land on this photo's
// actual lines.
private let courtSpots: [CourtSpot] = [
    CourtSpot(type: .freethrow,    nx: 0.50, ny: 0.70),  // ligne de lancer franc
    CourtSpot(type: .threeCenter,  nx: 0.50, ny: 0.28),  // 3pts sommet de l'arc
    CourtSpot(type: .threeRight45, nx: 0.75, ny: 0.35),  // 3pts aile droite ~45°
    CourtSpot(type: .threeLeft45,  nx: 0.25, ny: 0.35),  // 3pts aile gauche ~45°
    CourtSpot(type: .threeCornerR, nx: 0.93, ny: 0.80),  // 3pts coin droit
    CourtSpot(type: .threeCornerL, nx: 0.07, ny: 0.80),  // 3pts coin gauche
    CourtSpot(type: .midCenter,    nx: 0.50, ny: 0.50),  // mi-distance centre
    CourtSpot(type: .midRight,     nx: 0.74, ny: 0.62),  // mi-distance droite
    CourtSpot(type: .midLeft,      nx: 0.26, ny: 0.62),  // mi-distance gauche
]

struct CourtView: View {
    @EnvironmentObject var store: SessionStore

    @State private var isEditing = false
    @State private var dragOffsets: [ExerciseType: CGSize] = [:]
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let rect = courtRect(in: geo.size)

                    ZStack {
                        Image("CourtDiagram")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        ForEach(courtSpots, id: \.type) { spot in
                            let stats   = store.spotStats(for: spot.type)
                            let pos     = resolvedPosition(for: spot)
                            let baseX   = rect.minX + pos.nx * rect.width
                            let baseY   = rect.minY + (1.0 - pos.ny) * rect.height
                            let offset  = dragOffsets[spot.type] ?? .zero
                            let cx      = baseX + offset.width
                            let cy      = baseY + offset.height
                            let hasData = stats.totalShots > 0
                            let color   = hasData ? spotColor(stats.percentage) : Color(.systemFill)
                            let label   = hasData ? String(format: "%.0f%%", stats.percentage) : "–"

                            Group {
                                if isEditing {
                                    spotBubble(color: color, label: label)
                                        .overlay(
                                            Circle().strokeBorder(Color.orange,
                                                style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                        )
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    dragOffsets[spot.type] = value.translation
                                                }
                                                .onEnded { value in
                                                    let finalX = baseX + value.translation.width
                                                    let finalY = baseY + value.translation.height
                                                    let nx = min(max((finalX - rect.minX) / rect.width, 0), 1)
                                                    let ny = min(max(1 - (finalY - rect.minY) / rect.height, 0), 1)
                                                    store.setSpotPosition(spot.type, nx: nx, ny: ny)
                                                    dragOffsets[spot.type] = nil
                                                }
                                        )
                                } else {
                                    NavigationLink(destination: SpotDetailView(stats: stats)) {
                                        spotBubble(color: color, label: label)
                                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button(isEditing ? "Terminé" : "Modifier") {
                            isEditing.toggle()
                        }
                        .foregroundStyle(.orange)

                        if isEditing {
                            Button("Réinitialiser") {
                                showResetConfirmation = true
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        legendDot(Color(red: 0.2, green: 0.8, blue: 0.4), "≥70%")
                        legendDot(.orange, "50%")
                        legendDot(Color(red: 1, green: 0.2, blue: 0.2), "<50%")
                    }
                    .font(.caption2)
                }
            }
            .alert("Réinitialiser les positions ?", isPresented: $showResetConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Réinitialiser", role: .destructive) {
                    store.resetSpotPositions()
                }
            } message: {
                Text("Les repères retrouveront leur position d'origine sur le terrain.")
            }
        }
    }

    private func resolvedPosition(for spot: CourtSpot) -> SpotPosition {
        store.spotPositionOverrides[spot.type] ?? SpotPosition(nx: spot.nx, ny: spot.ny)
    }

    @ViewBuilder
    private func spotBubble(color: Color, label: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 44, height: 44)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
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

    // The image's own proportions define the displayed rect — same
    // centered, aspect-locked approach as the previous drawn-court fix
    // (never stretched), but the aspect ratio now comes from the photo's
    // actual pixel dimensions rather than a hardcoded court constant,
    // because the spots must line up with what's printed on THIS photo.
    private func courtRect(in size: CGSize) -> CGRect {
        let imgSize = UIImage(named: "CourtDiagram")?.size ?? size
        let aspect: CGFloat = imgSize.height == 0 ? 1 : imgSize.width / imgSize.height
        var w = size.width
        var h = w / aspect
        if h > size.height {
            h = size.height
            w = h * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Views/CourtView.swift
git commit -m "feat(ios): replace drawn court with photo, add draggable spot positions"
```

---

## Task 5: Manual verification in the simulator

**Files:** none (verification only)

### Context

This feature is fundamentally visual/interactive — whether the photo renders undistorted, whether spots track the finger, and whether dragged positions persist across relaunch can only be confirmed by actually running the app. This mirrors how the court-stretching fix earlier in this project was verified (build, install, screenshot, compare).

- [ ] **Step 1: Build for the simulator and locate the app bundle**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -5

APP=$(find ~/Library/Developer/Xcode/DerivedData \
  -path "*BasketTrainer*/Build/Products/Debug-iphonesimulator/BasketTrainer.app" \
  -not -path "*Index.noindex*" | head -1)
echo "$APP"
```

Expected: `** BUILD SUCCEEDED **` and a non-empty path ending in `BasketTrainer.app`.

- [ ] **Step 2: Boot the simulator, install, and launch**

```bash
xcrun simctl boot "iPhone 15" 2>/dev/null || true
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.tonnom.baskettrainer
```

- [ ] **Step 3: Navigate to "Terrain" and screenshot the default (non-edit) view**

Tap the "Terrain" tab (4th tab, court icon) in the simulator UI, then:

```bash
xcrun simctl io booted screenshot /tmp/court_default.png
```

Open `/tmp/court_default.png` and confirm:
- The court photo fills its area without stretching/distortion (proportions match the original 663×619 photo)
- All 9 colored spots render on top of the photo at roughly sensible court locations
- No part of the image is cropped or letterboxed oddly

- [ ] **Step 4: Enter edit mode and screenshot**

Tap "Modifier" in the top-left, then:

```bash
xcrun simctl io booted screenshot /tmp/court_editing.png
```

Open `/tmp/court_editing.png` and confirm:
- The toolbar button now reads "Terminé"
- A "Réinitialiser" button has appeared next to it
- Each spot now shows a dashed orange ring overlay (signaling it's draggable)

- [ ] **Step 5: Drag a spot and verify it persists across relaunch**

In the simulator, drag one spot (e.g., the center 3pt spot) to a clearly different location, tap "Terminé", then terminate and relaunch the app:

```bash
xcrun simctl terminate booted com.tonnom.baskettrainer
xcrun simctl launch booted com.tonnom.baskettrainer
xcrun simctl io booted screenshot /tmp/court_after_relaunch.png
```

Open `/tmp/court_after_relaunch.png`, navigate back to "Terrain", and confirm the dragged spot is still at its new (moved) location — proving `setSpotPosition` persisted to `UserDefaults` and reloaded on `init()`.

- [ ] **Step 6: Verify "Réinitialiser" restores defaults**

Tap "Modifier", then "Réinitialiser", confirm the alert, then screenshot:

```bash
xcrun simctl io booted screenshot /tmp/court_after_reset.png
```

Open `/tmp/court_after_reset.png` and confirm the previously-dragged spot has snapped back to its original default position from `courtSpots`.

This task has no commit — it's verification of the work already committed in Tasks 1–4. If any check fails, return to the relevant task, fix the root cause, and re-commit before re-running this verification.

---

## Self-Review

### Spec coverage (against `docs/superpowers/specs/2026-06-07-court-image-draggable-spots-design.md`)
- ✅ Court rendering replaced with `Image("CourtDiagram")` — Task 4, Step 1
- ✅ `aspectRatio(contentMode: .fit)`, centered, never stretched — Task 4, Step 1 (`courtRect` + `.frame`/`.position`)
- ✅ Spots positioned relative to the image's actual displayed rect — Task 4, Step 1 (`baseX`/`baseY` derived from `rect`)
- ✅ "Modifier"/"Terminé" edit-mode toggle in toolbar (not long-press) — Task 4, Step 1 (`isEditing`, `.topBarLeading`)
- ✅ Permanent persistence via `UserDefaults`/`Codable` — Task 3 (mirrors `watchSlots` save/load)
- ✅ `courtSpots` remains fallback/default, overrides layer on top — Task 4, Step 1 (`resolvedPosition`)
- ✅ "Réinitialiser" button (edit mode only) behind confirmation alert — Task 4, Step 1 (`showResetConfirmation`, `.alert`)
- ✅ `SpotPosition` struct (`nx`/`ny`, `Codable`) — Task 2
- ✅ `spotPositionOverrides`, `setSpotPosition`, `resetSpotPositions` — Task 3, Steps 1 & 3
- ✅ `[Int: SpotPosition]` wire format keyed by `rawValue`, unknown values skipped — Task 3, Step 4
- ✅ `basket_spot_positions` UserDefaults key — Task 3, Step 1
- ✅ Spots become plain draggable views (no `NavigationLink`) in edit mode, dashed ring overlay — Task 4, Step 1
- ✅ `DragGesture(minimumDistance: 0)` with live `dragOffsets` on `.onChanged`, normalize+clamp+persist on `.onEnded` — Task 4, Step 1
- ✅ Legend stays visible in both modes, unchanged placement — Task 4, Step 1 (`.topBarTrailing`, untouched from original)
- ✅ Asset catalog entry for the supplied photo — Task 1
- ✅ Drag-end-outside-image clamped to `0...1` — Task 4, Step 1 (`min(max(..., 0), 1)`)
- ✅ Missing/failed image asset degrades gracefully — Task 4, Step 1 (`UIImage(named:)?.size ?? size` fallback keeps `courtRect` valid; `Image("CourtDiagram")` renders blank per SwiftUI default, no crash)
- ✅ Unknown `ExerciseType` raw values skipped on decode — Task 3, Step 4 (`if let type = ExerciseType(rawValue:)`)
- ✅ Reset with empty overrides is a harmless no-op — Task 3, Step 3 (`resetSpotPositions` always assigns `[:]` and saves; assigning empty-to-empty is harmless)

### No placeholders
All steps contain complete, concrete code — no "TBD"/"add error handling"/"similar to Task N" patterns.

### Type consistency
- `SpotPosition(nx: CGFloat, ny: CGFloat)` defined in Task 2 — used identically in Task 3 (`SpotPosition(nx: nx, ny: ny)`) and Task 4 (`SpotPosition(nx: spot.nx, ny: spot.ny)`, `pos.nx`/`pos.ny`) ✅
- `store.spotPositionOverrides: [ExerciseType: SpotPosition]` declared in Task 3, Step 1 — read via `store.spotPositionOverrides[spot.type]` in Task 4's `resolvedPosition` ✅
- `store.setSpotPosition(_ type: ExerciseType, nx: CGFloat, ny: CGFloat)` declared in Task 3, Step 3 — called as `store.setSpotPosition(spot.type, nx: nx, ny: ny)` in Task 4 with matching label-less first argument and labeled `nx`/`ny` ✅
- `store.resetSpotPositions()` declared in Task 3, Step 3 — called as `store.resetSpotPositions()` in Task 4's alert action ✅
- `Image("CourtDiagram")` / `UIImage(named: "CourtDiagram")` — both reference the exact asset name created in Task 1 (`CourtDiagram.imageset`) ✅
- `courtSpots: [CourtSpot]` — kept as the same private array/struct from the original file (same 9 entries, same `nx`/`ny` values), only the rendering around it changes ✅

### Out of scope (per spec — intentionally not implemented)
Editing the image in-app, per-user/device profiles, undo/redo for drags, snap-back animation on reset.
