# Profile (Local) — Design Spec

**Date:** 2026-09-10
**Status:** Approved
**Scope:** A personal profile — username, display name, age, sex, position, photo, and computed global stats / per-category shot-zone performance — stored **entirely locally**, no backend. Bounded task: same pattern as `SessionStore`'s existing sub-stores (custom spots, trophies), not a new subsystem.

---

## Revision history

This spec went through two earlier drafts before landing here — kept for context, not because either is still relevant to what gets built:
1. **CloudKit** — dropped: requires a paid Apple Developer Program membership, which the user doesn't have.
2. **Firebase** (account + friends foundation, public profile documents, anonymous auth) — dropped: the user explicitly cancelled the friends/backend direction and asked for **just a local account**.

What follows describes only the local-only version actually being built. No backend, no accounts shareable between devices, no friends, no username uniqueness (nothing else exists to collide with).

---

## Decisions

| Topic | Decision |
|---|---|
| Storage | 100% local — `UserDefaults` + `JSONEncoder`/`JSONDecoder`, exactly the pattern every other piece of state in `SessionStore` already uses |
| Backend | None. No CloudKit, no Firebase, no networking of any kind for this feature |
| "Account" | Just a locally-stored profile tied to this install of the app — same durability as the rest of the app's data (survives relaunch, lost on delete/reinstall, exactly like session history today) |
| Username | Kept as a simple display field (the user typed "compte" — a name/handle feels right), but **not unique-checked** — there's nothing else to be unique against locally. If a shared/friends feature ever comes back, uniqueness enforcement gets added then, against whatever backend is chosen at that time |
| Shot-zone performance | Computed, not declared — per-category (Lancer Franc / 3 Points / Mi-distance / Technique) made/attempted/percentage, derived from local session history via `shotSegments`, same as `DayStats` |
| Global stats | Total sessions, total shots, overall FG%, longest streak (all-time) — mirrors `StatsView`, recomputed automatically whenever local session data changes |
| Photo | Compressed JPEG stored as raw `Data` in the profile struct — no size ceiling to design around now that it's not going into a network payload |
| State | New `ProfileStore` (`@Published`, `UserDefaults`-backed) — same shape as `SessionStore`, kept separate rather than bolted onto `SessionStore` (which is already large) |
| Entry point | Avatar button in `HomeView`'s toolbar (leading side, opposite the existing date), opens `ProfileView` as a sheet — no new tab |

---

## Data Model — new file `Models/UserProfile.swift`

```swift
import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case homme, femme, autre
    var id: String { rawValue }
    var label: String {
        switch self {
        case .homme: return "Homme"
        case .femme: return "Femme"
        case .autre: return "Autre"
        }
    }
}

enum PlayerPosition: String, Codable, CaseIterable, Identifiable {
    case meneur, arriere, ailier, ailierFort, pivot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .meneur:     return "Meneur"
        case .arriere:    return "Arrière"
        case .ailier:     return "Ailier"
        case .ailierFort: return "Ailier fort"
        case .pivot:      return "Pivot"
        }
    }
}

struct ZoneStat: Codable, Identifiable {
    var category: String   // "Lancer Franc" / "3 Points" / "Mi-distance" / "Technique"
    var shots: Int
    var made: Int
    var id: String { category }
    var percentage: Double { shots == 0 ? 0 : Double(made) / Double(shots) * 100 }
}

struct ProfileStatsSummary: Codable {
    var totalSessions: Int
    var totalShots: Int
    var overallFGPercentage: Double
    var longestStreak: Int
    var zonePerformance: [ZoneStat]

    static let empty = ProfileStatsSummary(totalSessions: 0, totalShots: 0,
                                            overallFGPercentage: 0, longestStreak: 0,
                                            zonePerformance: [])
}

struct UserProfile: Codable {
    var username: String
    var age: Int?
    var sex: Sex?
    var position: PlayerPosition?
    var photoData: Data?
    var statsSummary: ProfileStatsSummary
}
```

`ZoneStat.category` stays a plain `String` (not `ExerciseType`) — a denormalized display snapshot, independent of the trophy/exercise model evolving later.

---

## `ProfileStore` — new file `Models/ProfileStore.swift`

Same conventions as `SessionStore`'s sub-stores (compare `customSpots`/`unlockedTrophies`): a `@Published private(set)` value, a `UserDefaults` key, load/save pair, and — the one thing specific to this store — a Combine subscription to `SessionStore.shared.$sessions` so the stats summary and zone breakdown stay current automatically, the same reactive pattern the trophy engine already uses.

```swift
import Foundation
import Combine

class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profile: UserProfile? = nil

    private let storageKey = "basket_user_profile"
    private var cancellable: AnyCancellable?

    init() {
        load()
        cancellable = SessionStore.shared.$sessions
            .dropFirst()
            .sink { [weak self] sessions in
                self?.refreshStatsSummary(from: sessions)
            }
    }

    // ── Écriture ──

    func save(_ draft: UserProfile) {
        var toSave = draft
        toSave.statsSummary = Self.computeStatsSummary(from: SessionStore.shared.sessions)
        profile = toSave
        persist()
    }

    private func refreshStatsSummary(from sessions: [WorkoutSession]) {
        guard var updated = profile else { return }
        updated.statsSummary = Self.computeStatsSummary(from: sessions)
        profile = updated
        persist()
    }

    // ── Calcul des stats ──

    private static func computeStatsSummary(from sessions: [WorkoutSession]) -> ProfileStatsSummary {
        var totalShots = 0, madeShots = 0
        var byCategory: [String: (shots: Int, made: Int)] = [:]
        for session in sessions {
            for segment in session.shotSegments {
                totalShots += segment.totalShots
                madeShots  += segment.madeShots
                var entry = byCategory[segment.exerciseType.category] ?? (0, 0)
                entry.shots += segment.totalShots
                entry.made  += segment.madeShots
                byCategory[segment.exerciseType.category] = entry
            }
        }
        let categories = ["Lancer Franc", "3 Points", "Mi-distance", "Technique"]
        let zones = categories.map { cat -> ZoneStat in
            let entry = byCategory[cat] ?? (0, 0)
            return ZoneStat(category: cat, shots: entry.shots, made: entry.made)
        }
        return ProfileStatsSummary(
            totalSessions: sessions.count,
            totalShots: totalShots,
            overallFGPercentage: totalShots == 0 ? 0 : Double(madeShots) / Double(totalShots) * 100,
            longestStreak: longestStreak(from: sessions),
            zonePerformance: zones
        )
    }

    private static func longestStreak(from sessions: [WorkoutSession]) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, current = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev {
                let next = cal.date(byAdding: .day, value: 1, to: p)!
                current = cal.isDate(next, inSameDayAs: d) ? current + 1 : 1
            } else {
                current = 1
            }
            best = max(best, current)
            prev = d
        }
        return best
    }

    // ── Persistence ──

    private func persist() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(UserProfile?.self, from: data)
        else { return }
        profile = decoded
    }
}
```

---

## iOS UI Changes

### `HomeView.swift`

Add a leading toolbar item (the existing date stays trailing):

```swift
ToolbarItem(placement: .topBarLeading) {
    Button {
        activeSheet = .profile
    } label: {
        if let data = profileStore.profile?.photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }
}
```

`HomeSheet` gains a `.profile` case; `HomeView` gains `@EnvironmentObject var profileStore: ProfileStore`. On `.sheet` dispatch: `.profile` → `ProfileView()` if `profileStore.profile != nil`, else `EditProfileView(isOnboarding: true)`.

`BasketTrainerApp.swift` gains `@StateObject private var profileStore = ProfileStore.shared`, injected as an environment object alongside `store`/`garmin` — no launch-time async work needed (unlike the dropped backend drafts), since loading is synchronous local `UserDefaults` reads, already done in `ProfileStore.init()`.

### New file `Views/ProfileView.swift`

Read-only display: photo, username, a row of age/sex/position (whichever are set — omit blank ones), then the 4-tile global stats grid (same `StatTile` component `SessionDetailView` already defines: séances / tirs / FG% / meilleure série), then a compact zone breakdown (4 rows, category name + progress bar + percentage — reuses the visual language of `ExerciseStatRow` in `StatsView.swift`, not a copy of its code). A toolbar "Modifier" button pushes `EditProfileView(isOnboarding: false)`.

### New file `Views/EditProfileView.swift`

A `Form`: username (`TextField`), age (`Stepper` or numeric field), sex (segmented picker), position (picker), photo (`PhotosPicker` → compress to ~300×300 JPEG before storing in the draft). Save button disabled while username is empty. When `isOnboarding == true`, the nav title is "Compléter mon profil" and there's no cancel button (must save to dismiss); when editing an existing profile, both Cancel and Save are present. Calls `profileStore.save(draft)` on save, then dismisses — synchronous, no loading state, no error path (nothing to fail locally).

---

## Out of Scope

- Any backend, any account shareable across devices, any friends/social feature — explicitly cancelled by the user; would need its own future spec if revisited.
- Username uniqueness — meaningless without a shared namespace.
- Full session history export from the profile — only the lightweight `ProfileStatsSummary` snapshot is shown, not raw `WorkoutSession` data.
