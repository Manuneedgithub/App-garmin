# Trophy System — Design Spec

**Date:** 2026-09-08
**Status:** Approved
**Scope:** Add an achievement/trophy system to the iPhone app: 8 independent tracks (total shot volume, volume per exercise category, session count, training-day streak, best single-session accuracy, longest made-shot streak), each with 8 named tiers computed from the user's full session history, persisted once unlocked, celebrated on unlock, and browsable in a new "Trophées" tab.

---

## Problem

The app already tracks rich session history (`SessionStore.sessions`) and surfaces aggregate stats in `StatsView`, but there's no sense of long-term progression or milestones — no answer to "how close am I to 1000 free throws?" or "what's the longest streak I've ever had?". The user wants a trophy/achievement system with many tiers across several categories (shot volume overall, per exercise type, etc.) that unlock as historical totals cross thresholds, are visible on the iPhone, and — once earned — stay earned.

---

## Decisions

| Topic | Decision |
|---|---|
| Platform | iPhone only — trophies depend on full historical aggregates the watch never holds; no watch UI or sync involved |
| Tracks | 8: total shots, 4× per-category volume (Lancer Franc / 3 Points / Mi-distance / Technique), session count, training-day streak, best-session accuracy, longest made-shot streak |
| Tiers per track | 8, named Bronze → Argent → Or → Platine → Diamant → Maître → Champion → Légende (72 trophies total) |
| Custom spots | Count toward "Volume total" only; no dedicated track (thresholds wouldn't generalize across arbitrary user-defined spots) |
| Revocation | Never — once a tier is crossed it's recorded with a date and stays unlocked, even if the underlying session is later deleted |
| Unlock dates | Computed by replaying full history chronologically, so a trophy's date reflects the actual session where the threshold was first crossed — including retroactively, on first launch after this feature ships |
| Celebration | A popup overlay appears for genuinely new unlocks (post-launch), queued one at a time if several trigger together; the initial retroactive backfill is silent |
| Placement | New 5th tab, "Trophées" (`trophy.fill`), between Stats and Terrain |

---

## Tier Thresholds

| Track | Unit | Bronze…Légende |
|---|---|---|
| `totalShots` | tirs pris | 100 / 250 / 500 / 1000 / 2000 / 3500 / 5000 / 10000 |
| `freeThrowVolume` | tirs pris | same scale |
| `threePointVolume` | tirs pris | same scale |
| `midRangeVolume` | tirs pris | same scale |
| `techniqueVolume` | tirs pris | same scale |
| `sessionCount` | séances | 5 / 15 / 30 / 50 / 100 / 200 / 350 / 500 |
| `streakDays` | jours consécutifs | 3 / 5 / 7 / 14 / 21 / 30 / 60 / 100 |
| `bestAccuracy` | % de réussite sur une séance/série ≥ 15 tirs | 50 / 60 / 70 / 80 / 85 / 90 / 95 / 100 |
| `makeStreak` | tirs consécutifs réussis (au sein d'une même séance/série) | 5 / 10 / 15 / 20 / 30 / 40 / 50 / 75 |

Per-category volume uses `ExerciseType.category` ("Lancer Franc", "3 Points", "Mi-distance", "Technique") to bucket shots — the same grouping already used nowhere explicitly today but implied by `ExerciseType.category`.

---

## Data Model — new file `Models/Trophies.swift`

```swift
enum TrophyCategory: String, Codable, CaseIterable, Identifiable {
    case totalShots, freeThrowVolume, threePointVolume, midRangeVolume
    case techniqueVolume, sessionCount, streakDays, bestAccuracy, makeStreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalShots:       return "Volume total"
        case .freeThrowVolume:  return "Lancer Franc"
        case .threePointVolume: return "3 Points"
        case .midRangeVolume:   return "Mi-distance"
        case .techniqueVolume:  return "Technique"
        case .sessionCount:     return "Séances jouées"
        case .streakDays:       return "Régularité"
        case .bestAccuracy:     return "Meilleure séance"
        case .makeStreak:       return "Série de réussites"
        }
    }

    var icon: String {
        switch self {
        case .totalShots:                            return "🏀"
        case .freeThrowVolume, .bestAccuracy:         return "🎯"
        case .threePointVolume:                       return "🏹"
        case .midRangeVolume:                         return "🎳"
        case .techniqueVolume:                        return "↔️"
        case .sessionCount:                           return "📅"
        case .streakDays:                             return "🔥"
        case .makeStreak:                              return "⚡"
        }
    }

    var thresholds: [Int] {
        switch self {
        case .totalShots, .freeThrowVolume, .threePointVolume,
             .midRangeVolume, .techniqueVolume:
            return [100, 250, 500, 1000, 2000, 3500, 5000, 10000]
        case .sessionCount:  return [5, 15, 30, 50, 100, 200, 350, 500]
        case .streakDays:    return [3, 5, 7, 14, 21, 30, 60, 100]
        case .bestAccuracy:  return [50, 60, 70, 80, 85, 90, 95, 100]
        case .makeStreak:    return [5, 10, 15, 20, 30, 40, 50, 75]
        }
    }

    var unitSuffix: String { self == .bestAccuracy ? "%" : "" }

    // Which ExerciseType.category string feeds this track, if it's a volume-per-category track
    var exerciseCategoryFilter: String? {
        switch self {
        case .freeThrowVolume:  return "Lancer Franc"
        case .threePointVolume: return "3 Points"
        case .midRangeVolume:   return "Mi-distance"
        case .techniqueVolume:  return "Technique"
        default: return nil
        }
    }
}

enum TrophyTier {
    static let names  = ["Bronze", "Argent", "Or", "Platine", "Diamant", "Maître", "Champion", "Légende"]
    static let colorHex = ["#CD7F32", "#C0C0C0", "#FFD700", "#B9C6D6",
                            "#8CD9E0", "#7C5CD9", "#FF6600", "#FF3B8D"]
}

struct TrophyID: Hashable {
    let category: TrophyCategory
    let tierIndex: Int   // 0...7
    var storageKey: String { "\(category.rawValue)_\(tierIndex)" }
}
```

---

## Progress Engine — new file `Models/TrophyEngine.swift`

Pure, stateless: replays sessions chronologically once and returns the earliest date each `(category, tier)` pair was ever crossed. Called by `SessionStore`, never called directly by views.

```swift
enum TrophyEngine {
    static func computeUnlocks(from sessions: [WorkoutSession]) -> [TrophyID: Date] {
        var unlocked: [TrophyID: Date] = [:]
        let cal = Calendar.current
        var totalShots = 0
        var byCategory: [String: Int] = [:]
        var sessionCount = 0
        var bestAccuracyPct = 0
        var bestMakeStreak = 0
        var trainingDays: Set<Date> = []

        func record(_ category: TrophyCategory, _ value: Int, _ date: Date) {
            for (i, threshold) in category.thresholds.enumerated() {
                let id = TrophyID(category: category, tierIndex: i)
                if value >= threshold && unlocked[id] == nil { unlocked[id] = date }
            }
        }

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            sessionCount += 1
            trainingDays.insert(cal.startOfDay(for: session.date))

            for segment in session.shotSegments {
                totalShots += segment.totalShots
                byCategory[segment.exerciseType.category, default: 0] += segment.totalShots
                if segment.totalShots >= 15 {
                    let pct = Int(Double(segment.results.filter { $0 }.count)
                                  / Double(segment.totalShots) * 100)
                    bestAccuracyPct = max(bestAccuracyPct, pct)
                }
                bestMakeStreak = max(bestMakeStreak, longestRun(segment.results))
            }

            record(.totalShots, totalShots, session.date)
            for cat in [TrophyCategory.freeThrowVolume, .threePointVolume, .midRangeVolume, .techniqueVolume] {
                record(cat, byCategory[cat.exerciseCategoryFilter!] ?? 0, session.date)
            }
            record(.sessionCount, sessionCount, session.date)
            record(.streakDays, longestConsecutiveDayRun(trainingDays, cal: cal), session.date)
            record(.bestAccuracy, bestAccuracyPct, session.date)
            record(.makeStreak, bestMakeStreak, session.date)
        }
        return unlocked
    }

    private static func longestRun(_ bools: [Bool]) -> Int {
        var best = 0, current = 0
        for b in bools { current = b ? current + 1 : 0; best = max(best, current) }
        return best
    }

    private static func longestConsecutiveDayRun(_ days: Set<Date>, cal: Calendar) -> Int {
        var best = 0, current = 0
        var prev: Date? = nil
        for d in days.sorted() {
            if let p = prev, cal.isDate(cal.date(byAdding: .day, value: 1, to: p)!, inSameDayAs: d) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            prev = d
        }
        return best
    }
}
```

`session.shotSegments` is a small new computed property on `WorkoutSession` (in `Models.swift`) that normalizes simple vs. complex sessions into a uniform list — needed because volume/accuracy/streak math must walk `series` for complex sessions but the session itself for simple ones (the same split already handled ad hoc in `SessionStore.spotStats` and `ExerciseStats`):

```swift
struct ShotSegment { let exerciseType: ExerciseType; let totalShots: Int; let results: [Bool] }

extension WorkoutSession {
    var shotSegments: [ShotSegment] {
        if let series = series {
            return series.map { ShotSegment(exerciseType: $0.exerciseType, totalShots: $0.totalShots, results: $0.results) }
        }
        return [ShotSegment(exerciseType: exerciseType, totalShots: totalShots, results: results)]
    }
}
```

---

## `SessionStore` Changes

```swift
@Published private(set) var unlockedTrophies: [String: Date] = [:]   // TrophyID.storageKey -> unlock date
@Published var pendingCelebrations: [TrophyID] = []
private let trophiesKey = "basket_unlocked_trophies"

// called from init() after load(), and from add()
private func evaluateTrophies(announceNew: Bool) {
    let computed = TrophyEngine.computeUnlocks(from: sessions)
    var newlyUnlocked: [TrophyID] = []
    for (id, date) in computed where unlockedTrophies[id.storageKey] == nil {
        unlockedTrophies[id.storageKey] = date
        newlyUnlocked.append(id)
    }
    guard !newlyUnlocked.isEmpty else { return }
    persistTrophies()
    if announceNew {
        pendingCelebrations.append(contentsOf: newlyUnlocked.sorted { $0.category.rawValue < $1.category.rawValue })
    }
}

func dismissTopCelebration() {
    if !pendingCelebrations.isEmpty { pendingCelebrations.removeFirst() }
}

private func persistTrophies() {
    if let data = try? JSONEncoder().encode(unlockedTrophies) {
        UserDefaults.standard.set(data, forKey: trophiesKey)
    }
}

private func loadTrophies() {
    guard let data = UserDefaults.standard.data(forKey: trophiesKey),
          let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
    else { return }
    unlockedTrophies = decoded
}
```

`init()` calls `loadTrophies()` then `evaluateTrophies(announceNew: false)` (silent retroactive backfill — a fresh install of this feature awards all already-earned trophies without a burst of 20 popups). `add(_ session:)` calls `evaluateTrophies(announceNew: true)` at the end, after `save()`. `update(_:)` does the same for consistency, though no current flow edits sessions after the fact. `delete`/`deleteSession` call nothing new — thresholds are monotonic under the "never revoke" rule, so removing a session can never produce a *new* unlock, and existing ones are never taken back.

`unlockedTrophies` keyed by `String` (not `TrophyID` directly) because `TrophyID` isn't `Codable`-friendly as a dictionary key under `JSONEncoder`; `TrophyID(category:tierIndex:)` values are reconstructed from `storageKey` only where needed for display (splitting on `"_"`), which the UI layer handles via a small lookup built from `TrophyCategory.allCases × 0..<8` rather than parsing strings back.

---

## iOS UI — new file `Views/TrophiesView.swift`

- `NavigationStack` > `ScrollView` of one card per `TrophyCategory`, each showing:
  - Category icon + title, current value (e.g. "1 340 tirs" / "12 jours" / "87%")
  - A row of 8 tier pips (small circles/badges in `TrophyTier.colorHex[i]` when unlocked, gray/outline when locked), tappable to show that tier's threshold and unlock date (or "à débloquer : 2000 tirs" when locked)
  - A thin progress bar from the last unlocked threshold to the next one (mirrors the progress-bar visual language already used in `ExerciseStatRow`/`FatigueBar`)
- Reuses the app's existing card style (`Color(.systemBackground)`, `RoundedRectangle(cornerRadius: 16)`, orange accent) — no new visual language beyond the tier colors.

### `CelebrationOverlayView` (new, small)

```swift
struct CelebrationOverlayView: View {
    @EnvironmentObject var store: SessionStore
    var body: some View {
        if let id = store.pendingCelebrations.first {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(id.category.icon).font(.system(size: 56))
                    Text("Trophée débloqué !").font(.headline)
                    Text("\(TrophyTier.names[id.tierIndex]) · \(id.category.title)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .onTapGesture { store.dismissTopCelebration() }
            .transition(.scale.combined(with: .opacity))
        }
    }
}
```

### `ContentView.swift`

Adds the 5th tab and layers the celebration overlay above the whole `TabView` so it can interrupt any tab:

```swift
TabView { /* existing 4 tabs */
    TrophiesView().tabItem { Label("Trophées", systemImage: "trophy.fill") }
}
.overlay(CelebrationOverlayView())
```

---

## Out of Scope

- Any watch-side trophy display or sync — this is purely an iPhone feature over full local history.
- Custom spots getting their own per-spot volume track (only counted in the overall total).
- Social/sharing of unlocked trophies.
- Editing/retiring trophy definitions after the fact (thresholds are fixed constants; changing them later is a code change, not a user setting).
- Push notifications for unlocks while the app is backgrounded — the celebration overlay only fires while the app is open (e.g. right after a watch sync completes).
