# Custom Spots — Design Spec

**Date:** 2026-06-08
**Status:** Approved
**Scope:** Let the user create up to 5 custom shooting/training spots (name + emoji icon), place each on one of the 3 court pages, edit/delete them later, and keep the Garmin watch's exercise menu in sync whenever spots are added, edited, or removed.

---

## Problem

`CourtView` currently shows a fixed set of built-in spots (`shootingSpots`/`techniqueSpots`, backed by the fixed `ExerciseType` cases 0–10) across 3 court pages — including a "Réservé" page that's currently empty. The user wants to define their own spots (e.g. a specific angle or drill they practice), give each a name and an emoji, place it on whichever court makes sense, and have it behave exactly like a built-in spot: trackable from the iPhone, shown on the court with stats, and selectable from the watch's exercise menu — kept current on the watch as spots are added, renamed, or deleted.

---

## Decisions

| Topic | Decision |
|---|---|
| What a "custom spot" is | A new trackable exercise type (works through the existing tracking/stats/history pipeline) |
| Number of custom slots | Fixed pool of 5 (reserved `ExerciseType` IDs 11–15) |
| Icon source | Single emoji, typed via the system keyboard |
| Shot-type detail (catch & shoot / dribble / standing) | Same as built-ins — works automatically since the pipeline is generic |
| Historical sessions after a spot is renamed/deleted | Always show the spot's *current* name/icon (or a generic fallback if deleted) — no per-session snapshot |
| Choosing the court | Tap "+" directly on the court page you want — no separate court picker |
| Moving a spot to a different court | Not supported; delete and recreate (court is fixed at creation) |
| Watch sync trigger | Manual "Synchroniser" button — sends the *entire* current custom-spot list, full-replace semantics |

---

## Data Model Changes

### New: `CustomSpot` — `Models.swift`

```swift
struct CustomSpot: Codable, Identifiable, Equatable {
    var id: Int             // one of ExerciseType.customIDRange (11...15)
    var name: String
    var emoji: String       // single emoji
    var courtIndex: Int     // index into the 3 court pages — fixed at creation
    var position: SpotPosition   // starting nx/ny; reuses the existing struct
}
```

`position` is the spot's *starting* placement (defaults to court center, `nx: 0.5, ny: 0.5`, on creation). Subsequent dragging goes through the existing `spotPositionOverrides` mechanism — identical to built-in spots — so no changes are needed to the drag/reposition code path.

### Modified: `ExerciseType` — `Models.swift`

Add 5 reserved cases and a named range constant:

```swift
enum ExerciseType: Int, CaseIterable, Codable, Identifiable {
    case freethrow            = 0
    // … existing cases 1–10 unchanged …
    case formShotSideToSide   = 10
    case custom1              = 11
    case custom2              = 12
    case custom3              = 13
    case custom4              = 14
    case custom5              = 15

    static let customIDRange = 11...15
```

`.name` / `.emoji` resolve dynamically for custom cases by looking up the live definition in `SessionStore`, falling back to a generic placeholder when the slot is empty or its definition was deleted (this is the "always current name/icon" behavior — for a deleted spot, "current" means the generic fallback):

```swift
    private var customDefinition: CustomSpot? {
        SessionStore.shared.customSpots.first { $0.id == rawValue }
    }

    var name: String {
        if let custom = customDefinition { return custom.name }
        switch self {
        case .freethrow:            return "Lancer Franc"
        // … existing cases unchanged …
        case .formShotSideToSide:   return "Form Shot Side to Side"
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "Spot personnalisé"
        }
    }

    var emoji: String {
        if let custom = customDefinition { return custom.emoji }
        switch self {
        // … existing cases unchanged …
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "📍"
        }
    }

    var category: String {
        switch self {
        // … existing cases unchanged …
        case .custom1, .custom2, .custom3, .custom4, .custom5:
            return "Personnalisé"
        }
    }
```

`allCases` is overridden (the explicit implementation replaces the synthesized one — same mechanism the codebase already relies on for `Codable`/`Identifiable` customization) so that pickers, filters, and stats only ever see *configured* custom slots:

```swift
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

This is a deliberate dependency from `ExerciseType` (a model enum) onto the `SessionStore.shared` singleton. It's unusual for an enum, but it's the same singleton the rest of the app already depends on, and it means every existing call site that already works off `ExerciseType.name`/`.emoji`/`.allCases` — history filters, stats aggregation, the exercise picker in `ManualSessionView`, watch-slot series editors, court display, session detail — picks up custom spots **with zero changes**, instead of needing per-screen special-casing.

### Modified: `SessionStore`

```swift
@Published private(set) var customSpots: [CustomSpot] = []
private let customSpotsKey = "basket_custom_spots"
static let maxCustomSpots = 5

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
        resetSpotPositions(for: [type])   // drop any orphaned drag override
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

`loadCustomSpots()` is called from `init()` alongside `loadSlots()`/`loadSpotPositions()`. Persistence follows the exact `UserDefaults`/`JSONEncoder`/`JSONDecoder` pattern already used by `watchSlots` and `spotPositionOverrides` — no new infrastructure.

---

## iOS UI Changes

### `CourtView.swift`

**Dynamic page list.** The file-level `courtPages` constant stays as the source of built-in spots, but `CourtView` gains a computed property that merges in custom spots per court:

```swift
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
```

`body`, `refreshSpotStatsCache()`, and the reset-confirmation alert switch from referencing `courtPages` to `pages`. Everything downstream (rendering, drag-to-reposition, stats lookup, `resolvedPosition`) already works generically off `CourtSpot`/`ExerciseType` — no further changes needed there.

**Card needs to know its own page index.** `CourtPageCard` currently only receives `page: CourtPage`, which has no index of its own — but creating/editing a custom spot needs to know which of the 3 courts it belongs to. `CourtPageCard` gains `let pageIndex: Int`, and the call site becomes `ForEach(pages.indices, id: \.self) { index in CourtPageCard(page: pages[index], pageIndex: index, ...) }`.

**Add a spot.** `CourtPageCard` gains a "+" button in its header, shown only when `isEditing == true`. Tapping it:
- if `store.customSpots.count >= SessionStore.maxCustomSpots`, shows an alert "Limite atteinte (5/5)";
- otherwise presents `CustomSpotEditorView(editingSpot: nil, courtIndex: pageIndex)` as a sheet — the tapped court page *is* the chosen court, satisfying "choisir le terrain" with no separate picker.

**Edit / delete an existing custom spot.** In edit mode, a small pencil-badge overlay appears on spots whose `type.rawValue` falls in `ExerciseType.customIDRange` (built-in spots get no badge — they stay rename/delete-proof). Tapping the badge presents `CustomSpotEditorView(editingSpot: <existing CustomSpot>, courtIndex: pageIndex)`, pre-filled. The badge is a separate tap target from the existing drag gesture, so editing details and repositioning don't conflict.

**Sync button.** The toolbar (in edit mode, alongside "Modifier"/"Réinitialiser") gains "Synchroniser avec la montre", calling `garmin.sendCustomSpots(store.customSpots)`. `CourtView` adds `@EnvironmentObject var garmin: GarminManager` (already injected at the app root, so no wiring changes elsewhere). Feedback is shown via a new `garmin.lastCustomSpotsSendMessage` (mirrors `lastSlotSendMessage`: "✅ envoyé" / "Montre non connectée" / failure message).

### New: `CustomSpotEditorView.swift`

A sheet for both creating and editing a custom spot:

```swift
struct CustomSpotEditorView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    let editingSpot: CustomSpot?     // nil = creating; non-nil = editing
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
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

---

## Sync Mechanism — iPhone → Watch

### Modified: `GarminManager.swift`

Mirrors `sendSlot(_:template:)` exactly — same wake-then-send pattern (`openAppRequest` → `sendMessage`), same feedback-publishing style:

```swift
@Published var lastCustomSpotsSendMessage: String? = nil

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

The payload always carries the *complete* current list (full-replace semantics) — this is what lets the watch-side handler treat additions, edits, and deletions uniformly (see below), avoiding any drift between phone and watch state.

---

## Garmin (Watch) Changes

A grep for `EX_FREETHROW|EX_THREE|EX_MID|EX_FLOATER|EX_FORM_SHOT|exerciseId ==` across `garmin-app/source/*.mc` returns matches **only** in `ExerciseMenu.mc` — confirming the rest of the pipeline (`WorkoutView`, `SummaryView`, `ShotTypeMenu`, transmit) is generic over numeric exercise IDs and needs no changes. Only two files are touched:

### Modified: `BasketApp.mc`

Add a branch to `onPhoneAppMessage` for `"type": "customSpots"`. Because the iPhone always sends the full list, the watch can implement add/edit/delete uniformly: write each entry it received, and clear any of the 5 reserved slots that weren't included.

```monkeyc
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
    // Full-replace: clear any reserved slot the phone didn't include (covers deletions)
    for (var id = 11; id <= 15; id++) {
        if (!seenIds.hasKey(id)) {
            Application.Storage.setValue("customSpot_" + id.toString(), null);
        }
    }
}
```

### Modified: `ExerciseMenu.mc`

`getExerciseName(id)` gains a branch for IDs 11–15 that reads the stored definition:

```monkeyc
if (id >= 11 && id <= 15) {
    var def = Application.Storage.getValue("customSpot_" + id.toString());
    if (def instanceof Dictionary && def["name"] instanceof String) {
        return def["name"] as String;
    }
    return "Inconnu";
}
```

`ExerciseMenuView.initialize()` adds a dynamic loop after the existing static `addItem(...)` calls — same pattern as `SlotMenuView.initialize()` (loop over reserved storage keys, only add items that have data):

```monkeyc
for (var id = 11; id <= 15; id++) {
    var def = Application.Storage.getValue("customSpot_" + id.toString());
    if (def instanceof Dictionary && def["name"] instanceof String && def["emoji"] instanceof String) {
        addItem(new WatchUi.MenuItem(def["name"] as String, def["emoji"] as String, id, null));
    }
}
```

No other watch file changes — `WorkoutView`, `SummaryView`, `ShotTypeMenu`, and the transmit path already operate purely on the numeric `exerciseId` and accept 11–15 transparently.

---

## Out of Scope

- Moving a custom spot to a different court after creation (delete + recreate instead).
- Per-session historical snapshots of a spot's name/icon at the time it was recorded (the user explicitly chose "always show current name/icon").
- Automatic/background watch sync — sync is a deliberate, manual, full-replace action.
- Icon sources other than emoji (SF Symbols, custom images, etc.).
