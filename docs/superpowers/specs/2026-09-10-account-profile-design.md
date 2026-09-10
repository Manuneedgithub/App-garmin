# Account & Profile (Foundation) — Design Spec

**Date:** 2026-09-10
**Status:** Approved
**Scope:** First of several sub-projects toward accounts + friends. This one covers only: an implicit account, a public profile (username, display name, age, sex, position, photo, computed global stats and per-category shot-zone performance), and a "complete your profile" onboarding flow plus an edit flow. **No friends, no friend search, no viewing another user's profile** — those are separate, later sub-projects that this one's data model is deliberately shaped to support without rework.

---

## Problem

The app is entirely local today — no server, no networking beyond Bluetooth with the watch, no concept of a user identity beyond "whoever owns this phone." The user wants, eventually, to see friends' profiles (photo, age, sex, position, global stats, shot-zone performance). That requires data to live somewhere other than the viewing device, which means a backend. This spec builds only the foundation: an account (implicit, no login screen) and a profile that's readable by nobody but its owner yet — but stored in a shape a later "view a friend's profile" feature can read directly, with no migration.

**Revision note:** the first draft of this spec used CloudKit. Mid-design, the user confirmed they don't have a paid Apple Developer Program membership — and CloudKit requires one even for development-only use (a free "personal team" cannot use it at all). Rewritten around **Firebase** instead, which is free with just a Google account.

---

## Decisions

| Topic | Decision |
|---|---|
| Backend | **Firebase** (Firestore for data, Firebase Auth for identity) — free, no paid account of any kind needed |
| Sign-in | Implicit — **Firebase Anonymous Authentication** creates a stable identity on first launch with no login screen, no password, nothing to type. First launch with no profile → "Compléter mon profil" onboarding sheet |
| ⚠️ Known trade-off of anonymous auth | The anonymous identity is **local to the app install**, not tied to an Apple ID/iCloud account the way the original CloudKit design was. Deleting and reinstalling the app, or setting up the app on a second device, creates a *new* anonymous identity with no link back to the old profile. Out of scope to fix here (would mean adding real sign-in, e.g. Sign in with Apple linked to the anonymous account) — flagged so it's a known limitation, not a surprise later |
| Database | Firestore, two collections: `profiles/{uid}` (one doc per user) and `usernames/{username}` (reservation docs, see below) — public-readable now so a later friend-search/friend-profile feature reads the exact same documents with no migration |
| Username | Required at creation, globally unique — enforced via a Firestore **transaction** that atomically checks-and-reserves `usernames/{username}` before writing `profiles/{uid}`, the standard Firestore pattern for unique fields (Firestore has no native unique-constraint) |
| Shot-zone performance | **Computed**, not declared — per-category (Lancer Franc / 3 Points / Mi-distance / Technique) made/attempted/percentage, derived from local session history the same way `DayStats`/`TrophyEngine` already do. A compact 4-row breakdown, not a full per-spot heatmap |
| Global stats | Total sessions, total shots, overall FG%, longest streak (all-time) — mirrors what `StatsView` already shows, recomputed and republished automatically whenever local session data changes |
| Photo storage | Small compressed JPEG (~200×200, well under Firestore's 1 MiB document limit), stored **base64-encoded directly in the Firestore document** — not Firebase Storage. One less Firebase product to configure/secure for an avatar this small |
| State/transport split | New `FirebaseManager` (all `Auth`/`Firestore` calls) + new `ProfileStore` (`@Published` state, UserDefaults cache for offline-first reads) — mirrors the existing `GarminManager`/`SessionStore` split, rather than growing `SessionStore` further |
| Entry point | Avatar button in `HomeView`'s toolbar (leading side, opposite the existing date), opens `ProfileView` as a sheet — no new tab |
| Manual, out-of-my-control prerequisite | Create a free Firebase project at console.firebase.google.com, register an iOS app with bundle ID `com.tonnom.baskettrainer`, download `GoogleService-Info.plist` into the Xcode project, and add the Firebase iOS SDK via Swift Package Manager (`https://github.com/firebase/firebase-ios-sdk`, `FirebaseAuth` + `FirebaseFirestore` products). All free, all through a Google account — but requires the user's Firebase console access, which cannot be done by editing project files blindly |

---

## Data Model — new file `Models/UserProfile.swift`

Unchanged from the CloudKit draft — this part of the design never depended on which backend stores it:

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
    var uid: String              // Firebase Auth uid — the document ID in `profiles`
    var username: String
    var displayName: String
    var age: Int?
    var sex: Sex?
    var position: PlayerPosition?
    var photoBase64: String?     // small compressed JPEG, base64-encoded
    var statsSummary: ProfileStatsSummary
    var updatedAt: Date
}
```

`ZoneStat.category` stays a plain `String` (not `ExerciseType`) — a denormalized display snapshot, independent of the trophy/exercise model evolving later.

---

## `ProfileStore` — new file `Models/ProfileStore.swift`

Same shape as the CloudKit draft; only the calls into the manager change.

```swift
import Foundation
import Combine

class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profile: UserProfile? = nil
    @Published var lastSyncMessage: String? = nil

    private let cacheKey = "basket_user_profile"
    private var cancellable: AnyCancellable?

    init() {
        loadCache()
        cancellable = SessionStore.shared.$sessions
            .dropFirst()
            .sink { [weak self] sessions in
                self?.refreshStatsSummary(from: sessions)
            }
    }

    // ── Local cache ──

    private func saveCache() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return }
        profile = decoded
    }

    // ── Stats summary ──

    private func computeStatsSummary(from sessions: [WorkoutSession]) -> ProfileStatsSummary {
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
            longestStreak: Self.longestStreak(from: sessions),
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

    private func refreshStatsSummary(from sessions: [WorkoutSession]) {
        guard var updated = profile else { return }
        updated.statsSummary = computeStatsSummary(from: sessions)
        updated.updatedAt = Date()
        profile = updated
        saveCache()
        FirebaseManager.shared.pushProfile(updated) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure = result {
                    self?.lastSyncMessage = "Échec de synchronisation du profil"
                } else {
                    self?.lastSyncMessage = nil
                }
            }
        }
    }

    // ── Creation / edit ──

    // Called by EditProfileView on save. `draft.uid` is always the current Firebase uid
    // (set by the view from FirebaseManager.shared.currentUID before constructing the draft).
    func save(_ draft: UserProfile, completion: @escaping (Result<Void, ProfileError>) -> Void) {
        let usernameChanged = draft.username != profile?.username
        var toSave = draft
        toSave.statsSummary = computeStatsSummary(from: SessionStore.shared.sessions)
        toSave.updatedAt = Date()

        let write: () -> Void = { [weak self] in
            guard let self else { return }
            FirebaseManager.shared.pushProfile(toSave, reservingUsername: usernameChanged ? toSave.username : nil) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.profile = toSave
                        self.saveCache()
                        completion(.success(()))
                    case .failure(.usernameTaken):
                        completion(.failure(.usernameTaken))
                    case .failure:
                        completion(.failure(.syncFailed))
                    }
                }
            }
        }
        write()
    }

    // Called once at app launch if there's no local cache — covers the case where the
    // app was killed between anonymous sign-in and the first successful profile fetch.
    func fetchFromCloudIfNeeded(completion: @escaping (Bool) -> Void) {
        guard profile == nil else { completion(true); return }
        FirebaseManager.shared.fetchOwnProfile { [weak self] fetched in
            DispatchQueue.main.async {
                if let fetched {
                    self?.profile = fetched
                    self?.saveCache()
                }
                completion(fetched != nil)
            }
        }
    }
}

enum ProfileError: Error {
    case usernameTaken
    case syncFailed
}
```

---

## `FirebaseManager` — new file `Managers/FirebaseManager.swift`

Mirrors `GarminManager`'s role: the only file that imports `FirebaseAuth`/`FirebaseFirestore` directly.

```swift
import FirebaseAuth
import FirebaseFirestore
import Foundation

class FirebaseManager {
    static let shared = FirebaseManager()

    private let db = Firestore.firestore()

    var currentUID: String? { Auth.auth().currentUser?.uid }

    // Called once, early in app launch (BasketTrainerApp.init), before anything
    // else touches Firestore — ensures an anonymous identity always exists.
    func ensureSignedIn(completion: @escaping (Bool) -> Void) {
        if Auth.auth().currentUser != nil { completion(true); return }
        Auth.auth().signInAnonymously { result, error in
            completion(result != nil && error == nil)
        }
    }

    func fetchOwnProfile(completion: @escaping (UserProfile?) -> Void) {
        guard let uid = currentUID else { completion(nil); return }
        db.collection("profiles").document(uid).getDocument { snapshot, _ in
            completion(snapshot.flatMap(Self.profile(from:)))
        }
    }

    enum PushError: Error { case usernameTaken, notSignedIn, firestoreError }

    // `reservingUsername`: pass the new username only when it changed (or on first
    // creation) — triggers the atomic check-and-reserve transaction. Pass nil on a
    // plain stats/field update to skip the extra round-trip.
    func pushProfile(_ profile: UserProfile, reservingUsername: String? = nil,
                      completion: @escaping (Result<Void, PushError>) -> Void) {
        guard let uid = currentUID else { completion(.failure(.notSignedIn)); return }
        let profileRef = db.collection("profiles").document(uid)
        let data = Self.data(from: profile)

        guard let username = reservingUsername else {
            profileRef.setData(data, merge: true) { error in
                completion(error == nil ? .success(()) : .failure(.firestoreError))
            }
            return
        }

        let usernameRef = db.collection("usernames").document(username)
        db.runTransaction({ transaction, errorPointer -> Any? in
            let existing = try? transaction.getDocument(usernameRef)
            if let existing, existing.exists, existing.data()?["uid"] as? String != uid {
                errorPointer?.pointee = NSError(domain: "usernameTaken", code: 0)
                return nil
            }
            transaction.setData(["uid": uid], forDocument: usernameRef)
            transaction.setData(data, forDocument: profileRef, merge: true)
            return nil
        }) { _, error in
            if let error = error as NSError?, error.domain == "usernameTaken" {
                completion(.failure(.usernameTaken))
            } else if error != nil {
                completion(.failure(.firestoreError))
            } else {
                completion(.success(()))
            }
        }
    }

    // ── Firestore document <-> UserProfile ──

    private static func data(from profile: UserProfile) -> [String: Any] {
        var dict: [String: Any] = [
            "uid": profile.uid,
            "username": profile.username,
            "displayName": profile.displayName,
            "updatedAt": Timestamp(date: profile.updatedAt),
        ]
        if let age = profile.age { dict["age"] = age }
        if let sex = profile.sex { dict["sex"] = sex.rawValue }
        if let position = profile.position { dict["position"] = position.rawValue }
        if let photoBase64 = profile.photoBase64 { dict["photoBase64"] = photoBase64 }
        if let summaryData = try? JSONEncoder().encode(profile.statsSummary),
           let summaryDict = try? JSONSerialization.jsonObject(with: summaryData) {
            dict["statsSummary"] = summaryDict
        }
        return dict
    }

    private static func profile(from snapshot: DocumentSnapshot) -> UserProfile? {
        guard let data = snapshot.data(),
              let uid = data["uid"] as? String,
              let username = data["username"] as? String,
              let displayName = data["displayName"] as? String,
              let summaryDict = data["statsSummary"],
              let summaryData = try? JSONSerialization.data(withJSONObject: summaryDict),
              let summary = try? JSONDecoder().decode(ProfileStatsSummary.self, from: summaryData),
              let timestamp = data["updatedAt"] as? Timestamp
        else { return nil }

        return UserProfile(
            uid: uid,
            username: username,
            displayName: displayName,
            age: data["age"] as? Int,
            sex: (data["sex"] as? String).flatMap(Sex.init(rawValue:)),
            position: (data["position"] as? String).flatMap(PlayerPosition.init(rawValue:)),
            photoBase64: data["photoBase64"] as? String,
            statsSummary: summary,
            updatedAt: timestamp.dateValue()
        )
    }
}
```

### Firestore Security Rules (set once, in the Firebase console)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /profiles/{uid} {
      allow read: if true;                      // public — friends will read this later
      allow write: if request.auth != null && request.auth.uid == uid;
    }
    match /usernames/{username} {
      allow read: if true;
      // Only the transaction's own uid may claim a username, and a reservation is
      // immutable once created — closes the direct-write path a bare
      // "if request.auth != null" would leave open for hijacking someone else's
      // reservation from outside the app's transaction logic.
      allow create: if request.auth != null && request.resource.data.uid == request.auth.uid;
      allow update, delete: if false;
    }
  }
}
```

---

## iOS UI Changes

Unchanged from the CloudKit draft — the UI never talked to the backend directly, only through `ProfileStore`.

### `HomeView.swift`

Add a leading toolbar item (the existing date stays trailing):

```swift
ToolbarItem(placement: .topBarLeading) {
    Button {
        activeSheet = .profile
    } label: {
        if let base64 = profileStore.profile?.photoBase64,
           let data = Data(base64Encoded: base64), let uiImage = UIImage(data: data) {
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

`BasketTrainerApp.swift`: calls `FirebaseManager.shared.ensureSignedIn { _ in profileStore.fetchFromCloudIfNeeded { _ in } }` once in `.task` on `ContentView` (silent — no UI while it runs), and adds `FirebaseApp.configure()` in `init()`, before anything else, per Firebase's own setup requirement. Gains `@StateObject private var profileStore = ProfileStore.shared`, injected as an environment object alongside `store`/`garmin`.

### New file `Views/ProfileView.swift`

Read-only display: photo, display name + `@username`, a row of age/sex/position (whichever are set — omit blank ones), then the 4-tile global stats grid (same `StatTile` component `SessionDetailView` already defines: séances / tirs / FG% / meilleure série), then a compact zone breakdown (4 rows, category name + progress bar + percentage — reuses the visual language of `ExerciseStatRow` in `StatsView.swift`, not a copy of its code). A toolbar "Modifier" button pushes `EditProfileView(isOnboarding: false)`.

### New file `Views/EditProfileView.swift`

A `Form`: username (`TextField`, lowercase-only, disabled once already set unless the user explicitly wants to change it — changing it re-triggers the reservation transaction), display name, age (`Stepper` or numeric field), sex (segmented picker), position (picker), photo (`PhotosPicker` → compress to ~200×200 JPEG, base64-encode into the draft). Save button disabled while username/displayName are empty or a save is in flight; shows the specific error (`usernameTaken` / `syncFailed`) inline if `ProfileStore.save` fails. When `isOnboarding == true`, the nav title is "Compléter mon profil" and there's no cancel button (must save to dismiss); when editing an existing profile, both Cancel and Save are present.

---

## Manual Prerequisite (blocks real functionality, not compilation)

1. Create a free project at console.firebase.google.com (Google account, no payment).
2. Add an iOS app to it with bundle ID `com.tonnom.baskettrainer`; download the generated `GoogleService-Info.plist` and drag it into the Xcode project (target membership: BasketTrainer).
3. In Xcode: File → Add Package Dependencies → `https://github.com/firebase/firebase-ios-sdk` → add the `FirebaseAuth` and `FirebaseFirestore` products to the BasketTrainer target.
4. In the Firebase console, enable **Anonymous** sign-in under Authentication → Sign-in method.
5. In Firestore (create the database if not already done, "production mode"), paste the security rules above under Firestore → Rules.

None of this needs payment, but all of it needs the user's own Google/Firebase console access — cannot be done by editing project files blindly.

---

## Out of Scope

- Friend search, friend requests, viewing another user's profile — later sub-projects, unblocked by this one's data already living in a publicly-readable collection.
- Linking the anonymous account to a real credential (Sign in with Apple/Google) for cross-device/reinstall persistence — a real gap (see the flagged trade-off above), deliberately deferred rather than scope-creeping this sub-project.
- Editing/deleting the Firestore document from outside the app (account deletion flow) — not requested.
- Realtime listeners/push notifications (e.g. being notified when a friend's stats change) — not needed until friends exist; plain fetch-once reads are enough here.
- Any Android/web account surface — app is iPhone-only per current project direction.
- Full session history sync/backup to the backend — only the lightweight `ProfileStatsSummary` snapshot is published, not raw `WorkoutSession` data.
