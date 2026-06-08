# Custom Spots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user create up to 5 custom shooting spots (name + emoji), place each on one of the 3 court pages, edit/delete them, and keep the Garmin watch's exercise menu in sync via a manual "Synchroniser" action.

**Architecture:** Reserve `ExerciseType` raw values 11–15 for custom spots; their `.name`/`.emoji`/`.category`/`.allCases` resolve dynamically against a new `SessionStore.customSpots: [CustomSpot]` array (persisted in `UserDefaults`, same pattern as `watchSlots`). Because every existing screen already drives off `ExerciseType`, custom spots flow through history, stats, pickers, and the court map with no per-screen special-casing — only `CourtView` needs new UI to manage them. Sync to the watch mirrors the existing `sendSlot`/`onPhoneAppMessage`/`SlotMenu` pattern: a `{"type": "customSpots", "spots": [...]}` message, stored via `Application.Storage`, read dynamically when the exercise menu builds.

**Tech Stack:** Swift 5 / SwiftUI (iOS 16+), `UserDefaults`/`Codable` (existing `SessionStore` persistence pattern), Connect IQ SDK 9.1.0 / Monkey C (existing `Application.Storage` + `Communications` pattern). No external dependencies, no test target (this project has none — iOS verification is via `xcodebuild`; Garmin verification is the user's existing on-device/simulator workflow per `CLAUDE.md`).

**Design spec:** `docs/superpowers/specs/2026-06-08-custom-spots-design.md`

---

## File Map

- **Modify** `ios-app/BasketTrainer/Models/Models.swift` — add `CustomSpot` struct, `ExerciseType.customIDRange`, and extend `ExerciseType` with 5 reserved cases + dynamic `.name`/`.emoji`/`.category`/`.allCases`
- **Modify** `ios-app/BasketTrainer/Models/SessionStore.swift` — add `customSpots` storage, CRUD (`saveCustomSpot`/`deleteCustomSpot`/`nextAvailableCustomSpotID`), persistence
- **Modify** `ios-app/BasketTrainer/Managers/GarminManager.swift` — add `sendCustomSpots(_:)` + `lastCustomSpotsSendMessage`
- **Create** `ios-app/BasketTrainer/Views/CustomSpotEditorView.swift` — sheet for creating/editing/deleting a custom spot
- **Modify** `ios-app/BasketTrainer/Views/CourtView.swift` — dynamic per-court spot list, "+" to create, pencil badge to edit, "Synchroniser" button
- **Modify** `ios-app/BasketTrainer.xcodeproj/project.pbxproj` — register `CustomSpotEditorView.swift`
- **Modify** `garmin-app/source/BasketApp.mc` — handle `"type": "customSpots"` phone messages
- **Modify** `garmin-app/source/ExerciseMenu.mc` — resolve custom spot names + build dynamic menu items

---

## Task 1: iOS — `CustomSpot` model + reserved ID range

### Context

`Models.swift` already has `SpotPosition` (a plain `{nx, ny}` struct, lines 330–333) at the end of the file. `CustomSpot` reuses it for the spot's starting placement. The reserved-range constant (`11...15`) is added as a standalone `ExerciseType` extension here — *before* the new enum cases exist — so that `SessionStore` (Task 2) can reference `ExerciseType.customIDRange` without depending on Task 3's enum changes. This keeps every task independently compilable.

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift`

- [ ] **Step 1: Append `CustomSpot` and the reserved-range extension after `SpotPosition`**

At the end of `Models.swift` (after the closing brace of `SpotPosition` on line 333), add:

```swift

// ─────────────────────────────────────────────────
// Spot personnalisé créé par l'utilisateur
// ─────────────────────────────────────────────────
struct CustomSpot: Codable, Identifiable, Equatable {
    var id: Int             // un des ExerciseType.customIDRange (11...15)
    var name: String
    var emoji: String       // une seule emoji
    var courtIndex: Int     // index de la page-terrain — fixé à la création
    var position: SpotPosition   // position de départ ; ajustable ensuite par drag
}

extension ExerciseType {
    // Plage d'IDs réservée aux spots personnalisés (5 emplacements fixes)
    static let customIDRange = 11...15
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift
git commit -m "feat(ios): add CustomSpot model and reserved ID range"
```

---

## Task 2: iOS — Custom spots storage in `SessionStore`

### Context

`SessionStore` already persists `watchSlots` and `spotPositionOverrides` to `UserDefaults` via `JSONEncoder`/`JSONDecoder`, loaded in `init()`. `customSpots` follows the exact same shape: a `@Published private(set)` array, a storage key, `save`/`load` helpers, called from `init()`. `deleteCustomSpot` also clears any leftover drag-position override for that slot via the existing `resetSpotPositions(for:)` — otherwise a stale override could linger for a slot ID that's no longer in use.

**Files:**
- Modify: `ios-app/BasketTrainer/Models/SessionStore.swift`

- [ ] **Step 1: Add the published property, storage key, and limit constant**

Replace (lines 9–26):

```swift
class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions:   [WorkoutSession]   = []
    @Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: maxWatchSlots)
    @Published private(set) var spotPositionOverrides: [ExerciseType: SpotPosition] = [:]

    private let storageKey   = "basket_sessions"
    private let slotsKey     = "basket_watch_slots"
    private let spotPositionsKey = "basket_spot_positions"

    static let maxWatchSlots = 5

    init() {
        load()
        loadSlots()
        loadSpotPositions()
    }
```

With:

```swift
class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions:   [WorkoutSession]   = []
    @Published private(set) var watchSlots: [ComplexTemplate?] = Array(repeating: nil, count: maxWatchSlots)
    @Published private(set) var spotPositionOverrides: [ExerciseType: SpotPosition] = [:]
    @Published private(set) var customSpots: [CustomSpot] = []

    private let storageKey       = "basket_sessions"
    private let slotsKey         = "basket_watch_slots"
    private let spotPositionsKey = "basket_spot_positions"
    private let customSpotsKey   = "basket_custom_spots"

    static let maxWatchSlots  = 5
    static let maxCustomSpots = 5

    init() {
        load()
        loadSlots()
        loadSpotPositions()
        loadCustomSpots()
    }
```

- [ ] **Step 2: Add CRUD + persistence methods**

After the `// ── Spot Positions ──` section's closing brace (the end of `loadSpotPositions()`, just before the `// ── Persistence ──` comment on line 198), insert:

```swift

    // ── Custom Spots ──

    func saveCustomSpot(_ spot: CustomSpot) {
        if let i = customSpots.firstIndex(where: { $0.id == spot.id }) {
            customSpots[i] = spot
        } else {
            customSpots.append(spot)
        }
        persistCustomSpots()
    }

    func deleteCustomSpot(id: Int) {
        customSpots.removeAll { $0.id == id }
        if let type = ExerciseType(rawValue: id) {
            resetSpotPositions(for: [type])   // évite une position-override orpheline
        }
        persistCustomSpots()
    }

    func nextAvailableCustomSpotID() -> Int? {
        ExerciseType.customIDRange.first { id in !customSpots.contains { $0.id == id } }
    }

    private func persistCustomSpots() {
        if let data = try? JSONEncoder().encode(customSpots) {
            UserDefaults.standard.set(data, forKey: customSpotsKey)
        }
    }

    private func loadCustomSpots() {
        guard let data = UserDefaults.standard.data(forKey: customSpotsKey),
              let decoded = try? JSONDecoder().decode([CustomSpot].self, from: data)
        else { return }
        customSpots = decoded
    }
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Models/SessionStore.swift
git commit -m "feat(ios): add custom spots storage and CRUD to SessionStore"
```

---

## Task 3: iOS — Resolve custom spots dynamically in `ExerciseType`

### Context

This is the integration point that makes custom spots "just work" everywhere `ExerciseType` is already used (history, stats, pickers, court map). Add 5 reserved cases (`.custom1 = 11` … `.custom5 = 15`), then make `.name`/`.emoji` look up the live `CustomSpot` from `SessionStore.shared.customSpots` (falling back to a generic placeholder for empty/deleted slots — matching the spec decision "always show current name/icon"), give `.category` a fixed "Personnalisé" grouping, and override `allCases` so pickers/filters only ever see *configured* slots. Note `allCases` **replaces** the synthesized `CaseIterable` implementation — the same way this codebase already replaces synthesized `Codable`/`Identifiable` behavior with explicit code where needed.

This task depends on Tasks 1–2 (`CustomSpot`, `SessionStore.customSpots`, `ExerciseType.customIDRange` must already exist) — without them, `customDefinition`/`allCases` would not compile.

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift:8-62`

- [ ] **Step 1: Replace the entire `ExerciseType` enum body**

Replace lines 8–62 (from `enum ExerciseType: Int, CaseIterable, Codable, Identifiable {` through its closing `}`) with:

```swift
enum ExerciseType: Int, CaseIterable, Codable, Identifiable {
    case freethrow            = 0
    case threeCenter          = 1
    case threeRight45         = 2
    case threeLeft45          = 3
    case threeCornerR         = 4
    case threeCornerL         = 5
    case midCenter            = 6
    case midRight             = 7
    case midLeft              = 8
    case floater              = 9
    case formShotSideToSide   = 10
    case custom1              = 11
    case custom2              = 12
    case custom3              = 13
    case custom4              = 14
    case custom5              = 15

    var id: Int { rawValue }

    private var customDefinition: CustomSpot? {
        SessionStore.shared.customSpots.first { $0.id == rawValue }
    }

    var name: String {
        if let custom = customDefinition { return custom.name }
        switch self {
        case .freethrow:            return "Lancer Franc"
        case .threeCenter:          return "3pts Centre"
        case .threeRight45:         return "3pts 45° Droite"
        case .threeLeft45:          return "3pts 45° Gauche"
        case .threeCornerR:         return "3pts Coin Droite"
        case .threeCornerL:         return "3pts Coin Gauche"
        case .midCenter:            return "Mi-distance Centre"
        case .midRight:             return "Mi-distance Droite"
        case .midLeft:              return "Mi-distance Gauche"
        case .floater:              return "Flotteur"
        case .formShotSideToSide:   return "Form Shot Side to Side"
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "Spot personnalisé"
        }
    }

    var emoji: String {
        if let custom = customDefinition { return custom.emoji }
        switch self {
        case .freethrow:                        return "🎯"
        case .threeCenter:                      return "🏀"
        case .threeRight45, .threeLeft45:       return "↗️"
        case .threeCornerR, .threeCornerL:      return "📐"
        case .midCenter, .midRight, .midLeft:   return "🎳"
        case .floater:                          return "🪶"
        case .formShotSideToSide:               return "↔️"
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "📍"
        }
    }

    // Catégorie pour regrouper dans les stats
    var category: String {
        switch self {
        case .freethrow:                        return "Lancer Franc"
        case .threeCenter, .threeRight45,
             .threeLeft45, .threeCornerR,
             .threeCornerL:                     return "3 Points"
        case .midCenter, .midRight, .midLeft:   return "Mi-distance"
        case .floater, .formShotSideToSide:     return "Technique"
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "Personnalisé"
        }
    }

    // Remplace l'implémentation synthétisée de CaseIterable : seuls les
    // emplacements personnalisés *configurés* doivent apparaître dans les
    // pickers, filtres et stats — pas les 5 emplacements vides par défaut.
    static var allCases: [ExerciseType] {
        let builtIns: [ExerciseType] = [.freethrow, .threeCenter, .threeRight45, .threeLeft45,
                                        .threeCornerR, .threeCornerL, .midCenter, .midRight,
                                        .midLeft, .floater, .formShotSideToSide]
        let customs = SessionStore.shared.customSpots
            .sorted { $0.id < $1.id }
            .compactMap { ExerciseType(rawValue: $0.id) }
        return builtIns + customs
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift
git commit -m "feat(ios): resolve custom spot name/emoji dynamically in ExerciseType"
```

---

## Task 4: iOS — `GarminManager.sendCustomSpots`

### Context

Mirrors `sendSlot(_:template:)` (`GarminManager.swift:120-150`) exactly: same wake-then-send (`openAppRequest` → `sendMessage`), same `lastXSendMessage`-style published feedback property consumed by the UI. The payload always carries the *complete* current list — full-replace semantics, so the watch handler (Task 7) can treat add/edit/delete uniformly.

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

- [ ] **Step 1: Add the published feedback property**

Replace (line 16):

```swift
    @Published var lastSlotSendMessage: String? = nil
```

With:

```swift
    @Published var lastSlotSendMessage: String? = nil
    @Published var lastCustomSpotsSendMessage: String? = nil
```

- [ ] **Step 2: Add `sendCustomSpots(_:)` after `sendSlot`**

After the closing brace of `sendSlot(_:template:)` (ends at line 150, just before `func addMockSession()`), insert:

```swift

    func sendCustomSpots(_ spots: [CustomSpot]) {
        guard let device = connectedDevice else {
            lastCustomSpotsSendMessage = "Montre non connectée"
            return
        }
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        let payload: [String: Any] = [
            "type": "customSpots",
            "spots": spots.map { ["id": $0.id, "name": $0.name, "emoji": $0.emoji] }
        ]
        sdk.openAppRequest(app) { [weak self] _ in
            self?.sdk.sendMessage(payload, to: app, progress: nil) { result in
                print("sendCustomSpots → \(NSStringFromSendMessageResult(result))")
                DispatchQueue.main.async {
                    self?.lastCustomSpotsSendMessage = result == .success
                        ? "Spots personnalisés envoyés à la montre ✅"
                        : "Échec de l'envoi : \(NSStringFromSendMessageResult(result))"
                }
            }
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git commit -m "feat(ios): add GarminManager.sendCustomSpots"
```

---

## Task 5: iOS — `CustomSpotEditorView` + project registration

### Context

A single sheet handles both creating (`editingSpot == nil`) and editing (`editingSpot != nil`) a custom spot — name + single-emoji fields, plus a destructive "Supprimer" section shown only when editing, behind a confirmation alert (per spec: deleting affects the watch once synced). New spots start at the court's center (`nx: 0.5, ny: 0.5`); editing preserves the existing `position` (repositioning happens via the existing drag mechanism in `CourtView`, untouched here). The new file must be registered in `project.pbxproj` — follow the exact pattern used for `SlotsView.swift` (the most recently added view), continuing the `AA00000000000000000000XX` ID sequence from `EB` → `EC`/`ED`.

**Files:**
- Create: `ios-app/BasketTrainer/Views/CustomSpotEditorView.swift`
- Modify: `ios-app/BasketTrainer.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `CustomSpotEditorView.swift`**

```swift
import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR DE SPOT PERSONNALISÉ — création et modification
// ─────────────────────────────────────────────────

struct CustomSpotEditorView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    let editingSpot: CustomSpot?     // nil = création, sinon = modification
    let courtIndex: Int

    @State private var name: String
    @State private var emoji: String
    @State private var showDeleteConfirmation = false

    init(editingSpot: CustomSpot?, courtIndex: Int) {
        self.editingSpot = editingSpot
        self.courtIndex  = courtIndex
        _name  = State(initialValue: editingSpot?.name  ?? "")
        _emoji = State(initialValue: editingSpot?.emoji ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. Angle gauche profond", text: $name)
                }
                Section("Icône") {
                    TextField("Emoji", text: $emoji)
                        .onChange(of: emoji) { emoji = String(emoji.suffix(1)) }
                }
                if editingSpot != nil {
                    Section {
                        Button("Supprimer ce spot", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(editingSpot == nil ? "Nouveau spot" : "Modifier le spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .foregroundStyle(.orange)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || emoji.isEmpty)
                }
            }
            .alert("Supprimer ce spot ?", isPresented: $showDeleteConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { delete() }
            } message: {
                Text("Les séances déjà enregistrées resteront dans l'historique, mais ce spot ne sera plus affiché sur le terrain ni sur la montre une fois synchronisé.")
            }
        }
    }

    private func save() {
        guard let id = editingSpot?.id ?? store.nextAvailableCustomSpotID() else { return }
        let position = editingSpot?.position ?? SpotPosition(nx: 0.5, ny: 0.5)
        store.saveCustomSpot(CustomSpot(id: id, name: name, emoji: emoji,
                                        courtIndex: courtIndex, position: position))
        dismiss()
    }

    private func delete() {
        guard let spot = editingSpot else { return }
        store.deleteCustomSpot(id: spot.id)
        dismiss()
    }
}
```

- [ ] **Step 2: Register the file in `project.pbxproj`**

Use IDs `AA00000000000000000000EC` (fileRef) and `AA00000000000000000000ED` (buildFile) — the next unused pair after `SlotsView.swift`'s `EA`/`EB`.

Add to **PBXBuildFile section** (directly after the `SlotsView.swift in Sources` line, `AA00000000000000000000EB`):
```
		AA00000000000000000000ED /* CustomSpotEditorView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA00000000000000000000EC /* CustomSpotEditorView.swift */; };
```

Add to **PBXFileReference section** (directly after the `SlotsView.swift` line, `AA00000000000000000000EA`):
```
		AA00000000000000000000EC /* CustomSpotEditorView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CustomSpotEditorView.swift; sourceTree = "<group>"; };
```

Add to **Views group children** (directly after `AA00000000000000000000EA /* SlotsView.swift */,`):
```
				AA00000000000000000000EC /* CustomSpotEditorView.swift */,
```

Add to **Sources build phase** (directly after `AA00000000000000000000EB /* SlotsView.swift in Sources */,`):
```
			AA00000000000000000000ED /* CustomSpotEditorView.swift in Sources */,
```

- [ ] **Step 3: Build to verify it compiles and the new file is included**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios-app/BasketTrainer/Views/CustomSpotEditorView.swift \
        ios-app/BasketTrainer.xcodeproj/project.pbxproj
git commit -m "feat(ios): add CustomSpotEditorView for creating/editing custom spots"
```

---

## Task 6: iOS — Wire custom spots into `CourtView`

### Context

This is the largest task: `CourtView` currently renders a static `courtPages` constant. It needs a computed `pages` property that merges in `store.customSpots` per court, a "+" button per court card (visible in edit mode) to create a spot *on that court* — satisfying "choisir le terrain" by tapping where you want it — a pencil badge on existing custom spots to edit them, and a "Synchroniser" toolbar button. Sheet presentation is routed through a small `SpotEditorTarget` enum (`.create(courtIndex:)` / `.edit(CustomSpot)`) so one `.sheet(item:)` handles both creation and editing. `CourtPageCard` needs to know its own page index (it currently doesn't), since that's what determines which court a new spot belongs to.

Everything downstream of `page.spots` — rendering, drag-to-reposition, stats lookup via `resolvedPosition`/`spotStatsCache` — already works generically off `CourtSpot`/`ExerciseType` and needs **no changes**.

**Files:**
- Modify: `ios-app/BasketTrainer/Views/CourtView.swift`

- [ ] **Step 1: Add the `SpotEditorTarget` routing enum**

Replace (lines 96–99):

```swift
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

struct CourtView: View {
```

With:

```swift
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

// Cible de la feuille d'édition de spot personnalisé : création sur un
// terrain donné, ou modification d'un spot existant.
private enum SpotEditorTarget: Identifiable {
    case create(courtIndex: Int)
    case edit(CustomSpot)

    var id: String {
        switch self {
        case .create(let courtIndex): return "create-\(courtIndex)"
        case .edit(let spot):         return "edit-\(spot.id)"
        }
    }
}

struct CourtView: View {
```

- [ ] **Step 2: Add `garmin` environment object and new state**

Replace (lines 99–105):

```swift
struct CourtView: View {
    @EnvironmentObject var store: SessionStore

    @State private var period: CourtPeriod = .all
    @State private var isEditing = false
    @State private var dragOffsets: [ExerciseType: CGSize] = [:]
    @State private var showResetConfirmation = false
```

With:

```swift
struct CourtView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager

    @State private var period: CourtPeriod = .all
    @State private var isEditing = false
    @State private var dragOffsets: [ExerciseType: CGSize] = [:]
    @State private var showResetConfirmation = false
    @State private var spotEditorTarget: SpotEditorTarget? = nil
    @State private var showCustomSpotLimitAlert = false
```

- [ ] **Step 3: Add the `pages` computed property**

Replace (lines 114–119, the `filteredSessions` property through the start of `periodPicker`):

```swift
    private var filteredSessions: [WorkoutSession] {
        guard let start = period.startDate() else { return store.sessions }
        return store.sessions.filter { $0.date >= start }
    }

    private var periodPicker: some View {
```

With:

```swift
    private var filteredSessions: [WorkoutSession] {
        guard let start = period.startDate() else { return store.sessions }
        return store.sessions.filter { $0.date >= start }
    }

    // Fusionne les spots intégrés (statiques) avec les spots personnalisés
    // de l'utilisateur, groupés par terrain — page.spots reste la source
    // unique pour le rendu, le drag et les stats, sans changement ailleurs.
    private var pages: [CourtPage] {
        courtPages.enumerated().map { index, page in
            let customs = store.customSpots
                .filter { $0.courtIndex == index }
                .compactMap { spot -> CourtSpot? in
                    guard let type = ExerciseType(rawValue: spot.id) else { return nil }
                    return CourtSpot(type: type, nx: spot.position.nx, ny: spot.position.ny)
                }
            return CourtPage(title: page.title, subtitle: page.subtitle, spots: page.spots + customs)
        }
    }

    private var periodPicker: some View {
```

- [ ] **Step 4: Replace `body` and `refreshSpotStatsCache`, add `presentSpotEditor`**

Replace (lines 126–187, from `var body: some View {` through the closing brace of `CourtView`):

```swift
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        periodPicker
                        ForEach(courtPages.indices, id: \.self) { index in
                            CourtPageCard(
                                page: courtPages[index],
                                isEditing: isEditing,
                                dragOffsets: $dragOffsets,
                                spotStatsCache: spotStatsCache
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
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
            }
            .alert("Réinitialiser les positions ?", isPresented: $showResetConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Réinitialiser", role: .destructive) {
                    store.resetSpotPositions(for: courtPages.flatMap { $0.spots.map { $0.type } })
                }
            } message: {
                Text("Tous les repères retrouveront leur position d'origine sur chaque terrain.")
            }
            .onAppear(perform: refreshSpotStatsCache)
            .onReceive(store.$sessions) { _ in refreshSpotStatsCache() }
            .onChange(of: period) { _ in refreshSpotStatsCache() }
        }
    }

    private func refreshSpotStatsCache() {
        let allSpots   = courtPages.flatMap { $0.spots }
        let inPeriod   = filteredSessions
        spotStatsCache = Dictionary(uniqueKeysWithValues:
            allSpots.map { ($0.type, store.spotStats(for: $0.type, in: inPeriod)) })
    }
}
```

With:

```swift
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        periodPicker
                        ForEach(pages.indices, id: \.self) { index in
                            CourtPageCard(
                                page: pages[index],
                                pageIndex: index,
                                isEditing: isEditing,
                                dragOffsets: $dragOffsets,
                                spotStatsCache: spotStatsCache,
                                onAddSpot: { presentSpotEditor(forCourt: index) },
                                onEditCustomSpot: { spotEditorTarget = .edit($0) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
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

                            Button("Synchroniser") {
                                garmin.sendCustomSpots(store.customSpots)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .alert("Réinitialiser les positions ?", isPresented: $showResetConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Réinitialiser", role: .destructive) {
                    store.resetSpotPositions(for: pages.flatMap { $0.spots.map { $0.type } })
                }
            } message: {
                Text("Tous les repères retrouveront leur position d'origine sur chaque terrain.")
            }
            .alert("Limite atteinte (5/5)", isPresented: $showCustomSpotLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Supprimez un spot personnalisé existant avant d'en créer un nouveau.")
            }
            .sheet(item: $spotEditorTarget) { target in
                switch target {
                case .create(let courtIndex):
                    CustomSpotEditorView(editingSpot: nil, courtIndex: courtIndex)
                case .edit(let spot):
                    CustomSpotEditorView(editingSpot: spot, courtIndex: spot.courtIndex)
                }
            }
            .onAppear(perform: refreshSpotStatsCache)
            .onReceive(store.$sessions) { _ in refreshSpotStatsCache() }
            .onChange(of: period) { _ in refreshSpotStatsCache() }
        }
    }

    private func presentSpotEditor(forCourt courtIndex: Int) {
        if store.customSpots.count >= SessionStore.maxCustomSpots {
            showCustomSpotLimitAlert = true
        } else {
            spotEditorTarget = .create(courtIndex: courtIndex)
        }
    }

    private func refreshSpotStatsCache() {
        let allSpots   = pages.flatMap { $0.spots }
        let inPeriod   = filteredSessions
        spotStatsCache = Dictionary(uniqueKeysWithValues:
            allSpots.map { ($0.type, store.spotStats(for: $0.type, in: inPeriod)) })
    }
}
```

- [ ] **Step 5: Add `pageIndex`/callbacks to `CourtPageCard` and the "+" header button**

Replace (lines 192–213, the `CourtPageCard` declaration through the legend check):

```swift
private struct CourtPageCard: View {
    @EnvironmentObject var store: SessionStore

    let page: CourtPage
    let isEditing: Bool
    @Binding var dragOffsets: [ExerciseType: CGSize]
    let spotStatsCache: [ExerciseType: SpotStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(page.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !page.spots.isEmpty {
                legend
            }
```

With:

```swift
private struct CourtPageCard: View {
    @EnvironmentObject var store: SessionStore

    let page: CourtPage
    let pageIndex: Int
    let isEditing: Bool
    @Binding var dragOffsets: [ExerciseType: CGSize]
    let spotStatsCache: [ExerciseType: SpotStats]
    let onAddSpot: () -> Void
    let onEditCustomSpot: (CustomSpot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(page.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isEditing {
                    Button(action: onAddSpot) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !page.spots.isEmpty {
                legend
            }
```

- [ ] **Step 6: Add the pencil-edit badge for custom spots in the rendering loop**

Replace (lines 224–265, the `ForEach(page.spots, ...)` loop):

```swift
                    ForEach(page.spots, id: \.type) { spot in
                        let stats   = spotStatsCache[spot.type]
                            ?? SpotStats(exerciseType: spot.type, totalShots: 0, totalMade: 0, byType: [:])
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
```

With:

```swift
                    ForEach(page.spots, id: \.type) { spot in
                        let stats   = spotStatsCache[spot.type]
                            ?? SpotStats(exerciseType: spot.type, totalShots: 0, totalMade: 0, byType: [:])
                        let pos     = resolvedPosition(for: spot)
                        let baseX   = rect.minX + pos.nx * rect.width
                        let baseY   = rect.minY + (1.0 - pos.ny) * rect.height
                        let offset  = dragOffsets[spot.type] ?? .zero
                        let cx      = baseX + offset.width
                        let cy      = baseY + offset.height
                        let hasData = stats.totalShots > 0
                        let color   = hasData ? spotColor(stats.percentage) : Color(.systemFill)
                        let label   = hasData ? String(format: "%.0f%%", stats.percentage) : "–"
                        let custom  = store.customSpots.first { $0.id == spot.type.rawValue }

                        Group {
                            if isEditing {
                                spotBubble(color: color, label: label)
                                    .overlay(
                                        Circle().strokeBorder(Color.orange,
                                            style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if let custom {
                                            Button {
                                                onEditCustomSpot(custom)
                                            } label: {
                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white, .orange)
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                    }
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
```

- [ ] **Step 7: Build to verify it compiles**

```bash
xcodebuild -project ios-app/BasketTrainer.xcodeproj -scheme BasketTrainer \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add ios-app/BasketTrainer/Views/CourtView.swift
git commit -m "feat(ios): add custom spot creation, editing, and sync UI to CourtView"
```

---

## Task 7: Garmin — Sync custom spots into the watch exercise menu

### Context

A grep for `EX_FREETHROW|EX_THREE|EX_MID|EX_FLOATER|EX_FORM_SHOT|exerciseId ==` across `garmin-app/source/*.mc` matches **only** in `ExerciseMenu.mc` — the rest of the pipeline (`WorkoutView`, `SummaryView`, `ShotTypeMenu`, transmit) is generic over numeric IDs and accepts 11–15 transparently. Only two files change. `BasketApp.mc` stores each custom spot under `customSpot_<id>` via `Application.Storage` — exactly like `SlotMenu`'s `slot_<index>` keys — and, because the iPhone always sends the *complete* list, clears any of the 5 reserved slots that weren't included (covering deletions). `ExerciseMenu.mc` reads those back to resolve names and to build menu items dynamically, mirroring `SlotMenuView.initialize()`'s loop-and-check pattern.

This codebase's Garmin side is built/verified through the user's existing VS Code + simulator workflow on Windows (documented in `CLAUDE.md`) — there is no Mac-side build step in this plan, matching how the watch-slots plan (`docs/superpowers/plans/2026-06-06-watch-slots.md`, Task 1) handled Garmin changes (write + commit, no build step).

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`
- Modify: `garmin-app/source/ExerciseMenu.mc`

- [ ] **Step 1: Add the `"customSpots"` branch to `onPhoneAppMessage`**

Replace (lines 35–41 of `BasketApp.mc`):

```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("slot")) {
            if (!(dict["index"] instanceof Number) || !(dict["series"] instanceof Array)) { return; }
            var index  = dict["index"] as Number;
            if (index < 0 || index > 4) { return; }
            var series = dict["series"] as Array;
            Application.Storage.setValue("slot_" + index.toString(), series);
        }
    }
```

With:

```monkeyc
        if (dict["type"] instanceof String && (dict["type"] as String).equals("slot")) {
            if (!(dict["index"] instanceof Number) || !(dict["series"] instanceof Array)) { return; }
            var index  = dict["index"] as Number;
            if (index < 0 || index > 4) { return; }
            var series = dict["series"] as Array;
            Application.Storage.setValue("slot_" + index.toString(), series);
        }
        if (dict["type"] instanceof String && (dict["type"] as String).equals("customSpots")) {
            if (!(dict["spots"] instanceof Array)) { return; }
            var spots = dict["spots"] as Array;

            var seenIds = {};
            for (var i = 0; i < spots.size(); i++) {
                var entry = spots[i];
                if (!(entry instanceof Dictionary)) { continue; }
                var id = entry["id"];
                if (!(id instanceof Number) || id < 11 || id > 15) { continue; }
                if (!(entry["name"] instanceof String) || !(entry["emoji"] instanceof String)) { continue; }
                Application.Storage.setValue("customSpot_" + id.toString(),
                    { "name" => entry["name"], "emoji" => entry["emoji"] });
                seenIds[id] = true;
            }
            // Remplacement complet : tout emplacement réservé absent du
            // message est effacé — couvre les suppressions côté iPhone.
            for (var id = 11; id <= 15; id++) {
                if (!seenIds.hasKey(id)) {
                    Application.Storage.setValue("customSpot_" + id.toString(), null);
                }
            }
        }
    }
```

- [ ] **Step 2: Add the `Toybox.Application` import to `ExerciseMenu.mc`**

`ExerciseMenu.mc` currently imports only `Toybox.WatchUi` and `Toybox.Lang` — but resolving custom spot names requires `Application.Storage`. Replace (lines 1–2):

```monkeyc
import Toybox.WatchUi;
import Toybox.Lang;
```

With:

```monkeyc
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;
```

- [ ] **Step 3: Resolve custom spot names in `getExerciseName`**

Replace (lines 22–35, the entire `getExerciseName` function):

```monkeyc
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

With:

```monkeyc
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
    if (id >= 11 && id <= 15) {
        var def = Application.Storage.getValue("customSpot_" + id.toString());
        if (def instanceof Dictionary && def["name"] instanceof String) {
            return def["name"] as String;
        }
        return "Inconnu";
    }
    return "Inconnu";
}
```

- [ ] **Step 4: Add custom spots to the dynamic menu in `ExerciseMenuView.initialize()`**

Replace (lines 39–52, the `initialize` function):

```monkeyc
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

With:

```monkeyc
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

        // Spots personnalisés configurés depuis l'iPhone (emplacements 11-15) —
        // seuls ceux ayant une définition stockée apparaissent, comme SlotMenuView.
        for (var id = 11; id <= 15; id++) {
            var def = Application.Storage.getValue("customSpot_" + id.toString());
            if (def instanceof Dictionary && def["name"] instanceof String && def["emoji"] instanceof String) {
                addItem(new WatchUi.MenuItem(def["name"] as String, def["emoji"] as String, id, null));
            }
        }
    }
```

- [ ] **Step 5: Commit**

```bash
git add garmin-app/source/BasketApp.mc garmin-app/source/ExerciseMenu.mc
git commit -m "feat(garmin): sync custom spots from iPhone into the exercise menu"
```

---

## Manual Verification (for the user — not an agent task)

This project has no automated test target; verification is build-success (covered per-task above) plus hands-on testing, which the user has asked to handle personally rather than have the agent launch simulators. Once all 7 tasks are committed:

**iOS (in the Simulator):**
1. Open "Terrain" → "Modifier" → tap "+" on the "Zones de tir" card → create a spot named "Test Angle" with 🔥 → "Enregistrer". It should appear centered on that court.
2. Drag it to a new position; relaunch the app; confirm the position persisted.
3. Tap its pencil badge, rename it to "Test Angle 2", change the emoji, save — confirm the court label updates immediately.
4. Create 4 more custom spots (5 total); verify the "+" button now shows "Limite atteinte (5/5)".
5. Delete one spot via the editor's "Supprimer" (confirm the alert) — verify it disappears from the court and the "+" button works again.
6. Open "Nouvel entraînement" → confirm the remaining custom spots appear in the exercise picker, and a manual session can be logged against one (check it shows up in "Historique" and "Stats" with the right name/emoji).

**Watch sync (with a connected/paired Forerunner 255 or simulator, per the user's existing workflow):**
7. With at least one custom spot configured, tap "Synchroniser" in `CourtView`'s edit-mode toolbar; confirm the feedback message ("envoyé ✅" / "Montre non connectée").
8. On the watch, open the exercise menu — confirm the custom spot(s) appear with their current name + emoji, alongside the 11 built-ins.
9. Track a session against a custom spot on the watch; confirm it syncs back to the iPhone and displays with the correct name/emoji in history.
10. Rename or delete a custom spot on the iPhone, tap "Synchroniser" again, and confirm the watch's menu reflects the change (renamed item updates; deleted item disappears).

---

## Self-Review

### Spec coverage
- ✅ `CustomSpot` model + reserved ID range `11...15` — Task 1
- ✅ `SessionStore.customSpots` storage, persistence, CRUD (`saveCustomSpot`/`deleteCustomSpot`/`nextAvailableCustomSpotID`), 5-slot limit — Task 2
- ✅ `ExerciseType` extended with `.custom1`–`.custom5`, dynamic `.name`/`.emoji` via `customDefinition`, fixed `.category` "Personnalisé", overridden `allCases` showing only configured slots — Task 3
- ✅ `GarminManager.sendCustomSpots` + `lastCustomSpotsSendMessage`, full-list payload, wake-then-send pattern — Task 4
- ✅ `CustomSpotEditorView` create/edit/delete with confirmation alert, single-emoji capping, default center position — Task 5
- ✅ pbxproj registration — Task 5
- ✅ `CourtView`: dynamic `pages` merging custom spots per court, "+" button = court selection, pencil badge = edit (separate tap target from drag), "Synchroniser" button, limit alert — Task 6
- ✅ `BasketApp.mc` `"customSpots"` handler with full-replace semantics (covers add/edit/delete uniformly) — Task 7
- ✅ `ExerciseMenu.mc` `getExerciseName` fallback + dynamic menu item generation mirroring `SlotMenuView` — Task 7
- ✅ Out-of-scope items (cross-court move, historical snapshots, automatic sync, non-emoji icons) — intentionally absent from all tasks

### Placeholder scan
No "TBD"/"TODO"/"add appropriate handling" — every step shows complete, runnable code or exact shell commands with expected output.

### Type consistency
- `CustomSpot(id:name:emoji:courtIndex:position:)` — defined in Task 1, constructed identically in `CustomSpotEditorView.save()` (Task 5) and read in `CourtView.pages` (Task 6) ✅
- `store.saveCustomSpot(_:)` / `store.deleteCustomSpot(id:)` / `store.nextAvailableCustomSpotID()` — defined in Task 2, called with matching signatures in Task 5 ✅
- `garmin.sendCustomSpots(_ spots: [CustomSpot])` — defined in Task 4, called as `garmin.sendCustomSpots(store.customSpots)` in Task 6 ✅
- `ExerciseType.customIDRange` (`11...15`) — defined in Task 1, used in `nextAvailableCustomSpotID` (Task 2) and the watch-side range checks (Task 7, as literal `11`/`15` matching the same range) ✅
- `SessionStore.maxCustomSpots` (`5`) — defined in Task 2, used in `presentSpotEditor` (Task 6) ✅
- `SpotEditorTarget.create(courtIndex:)` / `.edit(CustomSpot)` — defined and consumed only within Task 6 (`onAddSpot`/`onEditCustomSpot` callbacks → `.sheet(item:)` switch) ✅
- `CourtPageCard(page:pageIndex:isEditing:dragOffsets:spotStatsCache:onAddSpot:onEditCustomSpot:)` — constructor call in `body` matches the struct's new property list exactly ✅
- `Application.Storage` key `"customSpot_" + id.toString()` — written in `BasketApp.mc` (Task 7, Step 1), read identically in `ExerciseMenu.mc` (Task 7, Steps 3–4) ✅
- Payload shape `{"type": "customSpots", "spots": [{"id", "name", "emoji"}]}` — produced in `GarminManager.sendCustomSpots` (Task 4), parsed with matching keys in `BasketApp.onPhoneAppMessage` (Task 7) ✅
