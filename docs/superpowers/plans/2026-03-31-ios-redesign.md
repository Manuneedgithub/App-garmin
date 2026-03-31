# iOS Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Moderniser l'interface iOS vers un style Light Clean avec dark mode adaptatif (suit le réglage système).

**Architecture:** Remplacement des couleurs hardcodées (`Color.black`, `Color.white.opacity(X)`) par les couleurs sémantiques iOS (`systemGroupedBackground`, `systemBackground`, etc.) qui s'adaptent automatiquement. Suppression du `.preferredColorScheme(.dark)` forcé. Aucun changement aux modèles de données ni à GarminManager.

**Tech Stack:** SwiftUI, iOS 16+, Swift Charts (déjà présent), SF Pro (système)

---

## Mapping de couleurs de référence

À appliquer dans toutes les tâches :

| Ancien | Nouveau |
|---|---|
| `Color.black.ignoresSafeArea()` | `Color(.systemGroupedBackground).ignoresSafeArea()` |
| `Color.white.opacity(0.05/0.06/0.07)` | `Color(.systemBackground)` |
| `Color.white.opacity(0.08/0.10)` | `Color(.secondarySystemBackground)` |
| `Color.white.opacity(0.1)` (barre progress) | `Color(.tertiarySystemFill)` |
| `.foregroundStyle(.white)` | `.foregroundStyle(.primary)` |
| `.colorScheme(.dark)` | _(supprimer)_ |
| `Color.white.opacity(0.3)` sur séparateurs | `Color(.separator)` |

Règle pourcentage (inchangée) : ≥70% → `.green` / ≥50% → `Color(hex:"FF6600")` / <50% → `.red`

Couleur orange : `Color(red: 1, green: 0.4, blue: 0)` ou `Color(.orange)` — utiliser `.orange` partout (SwiftUI tint = orange via `.accentColor(.orange)` dans ContentView).

---

## Task 1 : ContentView + BasketTrainerApp — Supprimer le dark mode forcé

**Files:**
- Modify: `ios-app/BasketTrainer/Views/ContentView.swift`
- Modify: `ios-app/BasketTrainer/BasketTrainerApp.swift`

- [ ] **Step 1 : Supprimer `.preferredColorScheme(.dark)` et adapter la nav bar**

Dans `ContentView.swift`, supprimer `.preferredColorScheme(.dark)` :

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.fill") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
        }
        .accentColor(.orange)
    }
}
```

Dans `BasketTrainerApp.swift`, supprimer `customizeAppearance()` et son appel (la nav bar UIKit avec texte blanc n'est plus nécessaire — SwiftUI gère l'adaptation) :

```swift
import SwiftUI

@main
struct BasketTrainerApp: App {
    @StateObject private var store  = SessionStore.shared
    @StateObject private var garmin = GarminManager.shared

    init() {
        GarminManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(garmin)
                .onOpenURL { url in
                    garmin.handleIncomingURL(url)
                }
        }
    }
}
```

- [ ] **Step 2 : Build pour vérifier**

`Cmd+B` dans Xcode. Attendu : 0 erreurs. L'app compile avec fond adaptatif sur toutes les vues (elles seront encore en noir car les vues ont leur propre `Color.black` — on les corrige dans les tâches suivantes).

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Views/ContentView.swift ios-app/BasketTrainer/BasketTrainerApp.swift
git commit -m "feat: remove forced dark mode, use system adaptive color scheme"
```

---

## Task 2 : Composants partagés — Couleurs adaptatives

**Files:**
- Modify: `ios-app/BasketTrainer/Views/WorkoutConfigView.swift` (contient `SectionLabel`, `ExerciseOptionRow`, `ShotCountChip`)
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift` (contient `SessionRowView`, `MiniStatCard`)

Ces sous-composants sont utilisés dans plusieurs vues. Les mettre à jour en premier évite de casser les builds des tâches suivantes.

- [ ] **Step 1 : Mettre à jour les composants dans WorkoutConfigView.swift**

Remplacer les structs `SectionLabel`, `ExerciseOptionRow`, `ShotCountChip` à la fin du fichier :

```swift
struct SectionLabel: View {
    let title: String
    let icon:  String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct ExerciseOptionRow: View {
    let exercise:   ExerciseType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(exercise.emoji).font(.title3)
            Text(exercise.name)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ShotCountChip: View {
    let count:      Int
    let isSelected: Bool

    var body: some View {
        Text("\(count)")
            .font(.subheadline.bold())
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2 : Mettre à jour MiniStatCard et SessionRowView dans HomeView.swift**

Remplacer `MiniStatCard` :

```swift
struct MiniStatCard: View {
    let value: String
    let label: String
    let icon:  String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

Remplacer `SessionRowView` :

```swift
struct SessionRowView: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 14) {
            Text(session.displayEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if session.isComplex {
                        Text("\(session.series?.count ?? 0) séries")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    if session.sentFromWatch {
                        Text("⌚")
                            .font(.caption2)
                    }
                }
                HStack(spacing: 4) {
                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                    if let dur = session.duration, dur > 0 {
                        Text("·")
                        Text("\(Int(dur / 60)) min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.madeShots)/\(session.totalShots)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", session.percentage))
                    .font(.caption.bold())
                    .foregroundStyle(percentageColor(session.percentage))
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
```

- [ ] **Step 3 : Build**

`Cmd+B`. Attendu : 0 erreurs.

- [ ] **Step 4 : Commit**

```bash
git add ios-app/BasketTrainer/Views/WorkoutConfigView.swift ios-app/BasketTrainer/Views/HomeView.swift
git commit -m "feat: update shared components to adaptive colors"
```

---

## Task 3 : HomeView — Redesign complet

**Files:**
- Modify: `ios-app/BasketTrainer/Views/HomeView.swift`

- [ ] **Step 1 : Réécrire HomeView**

Remplacer la struct `HomeView` (lignes 6–146) par :

```swift
struct HomeView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    @State private var showManualEntry  = false
    @State private var prefillTemplate: ComplexTemplate? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        if garmin.guidedTemplate != nil {
                            GuidedSessionBanner()
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        quickStats
                            .padding(.horizontal, 20)

                        newWorkoutButton
                            .padding(.horizontal, 20)

                        if !store.templates.isEmpty {
                            templatesSection
                        }

                        if !store.recentSessions.isEmpty {
                            recentSessionsList
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.3), value: garmin.guidedTemplate != nil)
                }
            }
            .navigationTitle("Basket Trainer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showManualEntry, onDismiss: { prefillTemplate = nil }) {
                ManualSessionView(prefillTemplate: prefillTemplate)
            }
        }
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            MiniStatCard(value: "\(store.totalSessions)", label: "Séances",  icon: "figure.basketball")
            MiniStatCard(value: "\(store.totalShots)",   label: "Tirs",      icon: "basketball")
            MiniStatCard(value: String(format: "%.0f%%", store.overallPct),  label: "Réussite", icon: "percent")
        }
    }

    private var newWorkoutButton: some View {
        Button {
            prefillTemplate = nil
            showManualEntry = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouvel entraînement")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Saisie manuelle ou depuis la montre")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Templates")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.templates) { template in
                        Button {
                            prefillTemplate = template
                            showManualEntry = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(template.series.count) séries · \(template.series.reduce(0) { $0 + $1.totalShots }) tirs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: 3)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Récentes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            ForEach(store.recentSessions.prefix(5)) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2 : Mettre à jour GuidedSessionBanner dans TemplatesView.swift**

Dans `TemplatesView.swift`, remplacer le `.background(...)` de `bannerContent` :

```swift
// Avant (ligne ~233):
.background(
    RoundedRectangle(cornerRadius: 16)
        .fill(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
)

// Après:
.background(
    RoundedRectangle(cornerRadius: 16)
        .fill(Color(.systemBackground))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
)
```

- [ ] **Step 3 : Build + run simulateur**

`Cmd+R`. Vérifier : fond gris clair / noir selon mode système, cartes blanches, bouton orange, templates en scroll horizontal.

- [ ] **Step 4 : Commit**

```bash
git add ios-app/BasketTrainer/Views/HomeView.swift ios-app/BasketTrainer/Views/TemplatesView.swift
git commit -m "feat: redesign HomeView with adaptive colors and horizontal templates"
```

---

## Task 4 : HistoryView — Chips + recherche + groupes iOS natifs

**Files:**
- Modify: `ios-app/BasketTrainer/Views/HistoryView.swift`

- [ ] **Step 1 : Réécrire HistoryView**

Remplacer tout le contenu de `HistoryView.swift` :

```swift
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filterCategory: String? = nil
    @State private var searchText = ""
    @State private var showManualEntry = false

    private let categories = ["Lancer Franc", "3 Points", "Mi-distance"]

    private var filteredSessions: [WorkoutSession] {
        var sessions = store.sessions.sorted { $0.date > $1.date }

        if let cat = filterCategory {
            sessions = sessions.filter { s in
                if let series = s.series {
                    return series.contains { $0.exerciseType.category == cat }
                }
                return s.exerciseType.category == cat
            }
        }

        if !searchText.isEmpty {
            sessions = sessions.filter { s in
                s.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return sessions
    }

    private var groupedByDate: [(key: String, sessions: [WorkoutSession])] {
        let dict = Dictionary(grouping: filteredSessions) { session -> String in
            let cal = Calendar.current
            if cal.isDateInToday(session.date) { return "Aujourd'hui" }
            if cal.isDateInYesterday(session.date) { return "Hier" }
            return session.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        let keys = dict.keys.sorted { a, b in
            if a == "Aujourd'hui" { return true }
            if b == "Aujourd'hui" { return false }
            if a == "Hier" { return true }
            if b == "Hier" { return false }
            let da = dict[a]!.first!.date
            let db = dict[b]!.first!.date
            return da > db
        }
        return keys.map { (key: $0, sessions: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Group {
                    if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        sessionList
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Rechercher...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualSessionView()
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Tous", isSelected: filterCategory == nil) {
                    filterCategory = nil
                }
                ForEach(categories, id: \.self) { cat in
                    FilterChip(label: cat, isSelected: filterCategory == cat) {
                        filterCategory = filterCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterChips
                    .padding(.bottom, 8)

                ForEach(groupedByDate, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.key)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        VStack(spacing: 1) {
                            ForEach(group.sessions) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    SessionRowView(session: session)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteSession(session)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            filterChips
            Spacer()
            Image(systemName: "basketball")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.5))
            Text("Aucune séance")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(filterCategory == nil && searchText.isEmpty
                 ? "Lance un entraînement depuis la montre\nou ajoute-en une manuellement."
                 : "Aucun résultat pour ce filtre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if filterCategory == nil && searchText.isEmpty {
                Button {
                    showManualEntry = true
                } label: {
                    Label("Ajouter manuellement", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }
}

struct FilterChip: View {
    let label:      String
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.orange : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color(.separator), lineWidth: isSelected ? 0 : 0.5)
                )
        }
    }
}
```

Note : `FilterSheet` est supprimée (remplacée par les chips). Le filtre est maintenant par catégorie (Lancer Franc / 3 Points / Mi-distance) au lieu de par exercice exact — plus lisible.

- [ ] **Step 2 : Build + run**

`Cmd+R`. Vérifier : chips de filtre, barre de recherche, groupes "Aujourd'hui" / "Hier" / date, swipe to delete, badges ⌚ et "N séries" dans `SessionRowView`.

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Views/HistoryView.swift
git commit -m "feat: redesign HistoryView with filter chips, searchable, grouped list"
```

---

## Task 5 : StatsView — Période + couleurs adaptatives

**Files:**
- Modify: `ios-app/BasketTrainer/Views/StatsView.swift`

- [ ] **Step 1 : Mettre à jour StatsPeriod**

Remplacer l'enum `StatsPeriod` (lignes 8–41) :

```swift
enum StatsPeriod: String, CaseIterable {
    case week7  = "7j"
    case month  = "30j"
    case month3 = "3m"
    case all    = "Tout"

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:    return nil
        case .week7:  return cal.date(byAdding: .day,   value: -7,  to: now)
        case .month:  return cal.date(byAdding: .day,   value: -30, to: now)
        case .month3: return cal.date(byAdding: .month, value: -3,  to: now)
        }
    }

    func previousStartDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return nil
        case .week7:
            return cal.date(byAdding: .day, value: -14, to: now)
        case .month:
            return cal.date(byAdding: .day, value: -60, to: now)
        case .month3:
            return cal.date(byAdding: .month, value: -6, to: now)
        }
    }
}
```

Aussi mettre à jour `previousSessions` dans StatsView pour correspondre :

```swift
private var previousSessions: [WorkoutSession] {
    guard let prevStart = period.previousStartDate(),
          let currStart = period.startDate() else { return [] }
    return store.sessions.filter { $0.date >= prevStart && $0.date < currStart }
}
```

Et `pctChange` :

```swift
private var pctChange: Double? {
    guard period != .all, !previousSessions.isEmpty else { return nil }
    return filteredOverallPct - previousOverallPct
}
```

- [ ] **Step 2 : Adapter le fond et les cards**

Dans `StatsView.body`, remplacer `Color.black.ignoresSafeArea()` :

```swift
Color(.systemGroupedBackground).ignoresSafeArea()
```

Dans `progressChart` (var progressChart), remplacer :
```swift
// Avant
.background(Color.white.opacity(0.05))
// Après
.background(Color(.systemBackground))
```

Dans `calendarHeatmap`, remplacer :
```swift
// Avant
.background(Color.white.opacity(0.05))
// Après
.background(Color(.systemBackground))
```

Dans `recordsSection`, remplacer le `.background(Color.white.opacity(0.05))` du container et des rows :
```swift
// Container
.background(Color(.systemBackground))
// Rows internes (padding(14).background)
.background(Color(.secondarySystemBackground))
```

Dans `fatigueSection`, remplacer :
```swift
.background(Color.white.opacity(0.05)) → .background(Color(.systemBackground))
```

- [ ] **Step 3 : Adapter GlobalStatCard, ExerciseStatRow, FatigueBar**

Remplacer `GlobalStatCard` :

```swift
struct GlobalStatCard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

Remplacer `ExerciseStatRow` :

```swift
struct ExerciseStatRow: View {
    let stats: ExerciseStats

    private var pctColor: Color {
        if stats.avgPercentage >= 70 { return .green }
        if stats.avgPercentage >= 50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(stats.exerciseType.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.exerciseType.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(stats.totalSessions) séance\(stats.totalSessions > 1 ? "s" : "") · \(stats.totalShots) tirs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", stats.avgPercentage))
                    .font(.title3.bold())
                    .foregroundStyle(pctColor)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pctColor)
                        .frame(width: geo.size.width * (stats.avgPercentage / 100), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

Remplacer `FatigueBar` :

```swift
struct FatigueBar: View {
    let label: String
    let pct:   Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(pct / 100, 1.0), height: 8)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", pct))
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
```

- [ ] **Step 4 : Mettre à jour les couleurs dans globalSummary**

Dans la propriété `globalSummary`, remplacer les `.background(Color.white.opacity(0.06))` des deux cards (réussite + streak) par `.background(Color(.systemBackground))`.

Dans HotZonesView, le `drawCourt` dessine sur un fond bois — garder tel quel (le canvas est self-contained).

- [ ] **Step 5 : Build + run**

`Cmd+R`. Vérifier : sélecteur période "7j/30j/3m/Tout", fond adaptatif, cartes blanches/sombres, heatmap et hot zones intacts.

- [ ] **Step 6 : Commit**

```bash
git add ios-app/BasketTrainer/Views/StatsView.swift
git commit -m "feat: redesign StatsView with adaptive colors and updated period labels"
```

---

## Task 6 : SessionDetailView — Header unifié + couleurs adaptatives

**Files:**
- Modify: `ios-app/BasketTrainer/Views/SessionDetailView.swift`

- [ ] **Step 1 : Adapter le fond et les cards de SessionDetailView**

Remplacer `Color.black.ignoresSafeArea()` par `Color(.systemGroupedBackground).ignoresSafeArea()`.

Remplacer `scoreHeader` :

```swift
private var scoreHeader: some View {
    VStack(spacing: 0) {
        // Identité exercice
        HStack(spacing: 12) {
            Text(current.displayEmoji)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(current.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(current.date.formatted(.dateTime.day().month().hour().minute()))
                    if let dur = current.duration, dur > 0 {
                        Text("·")
                        Text("\(Int(dur / 60)) min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)

        Divider()

        // Score
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(current.madeShots)/\(current.totalShots)")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", current.percentage))
                    .font(.title.bold())
                    .foregroundStyle(percentageColor(current.percentage))
                    .monospacedDigit()
                Text(current.performanceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)

        Divider()

        // Barre de progression
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 5)
                Rectangle()
                    .fill(percentageColor(current.percentage))
                    .frame(width: geo.size.width * CGFloat(current.percentage / 100), height: 5)
            }
        }
        .frame(height: 5)
    }
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
}
```

Remplacer `statsGrid` (les 3 tiles sous le header) par une version sans doublon avec le header — afficher uniquement réussis / ratés puisque le score total est déjà dans le header :

```swift
private var statsGrid: some View {
    HStack(spacing: 12) {
        StatTile(value: "\(current.madeShots)",   label: "Réussis", color: .green)
        StatTile(value: "\(current.missedShots)",  label: "Ratés",   color: .red)
        StatTile(value: "\(current.totalShots)",   label: "Total",   color: .orange)
    }
}
```

Remplacer `StatTile` :

```swift
struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

Remplacer les `.background(Color.white.opacity(0.05/0.06))` dans `seriesList` et `shotsGrid` par `.background(Color(.systemBackground))` et les `.background(Color.white.opacity(0.06))` des rows internes par `.background(Color(.secondarySystemBackground))`.

Remplacer `metaInfo` :

```swift
private var metaInfo: some View {
    VStack(alignment: .leading, spacing: 8) {
        InfoRow(icon: "calendar",
                label: "Date",
                value: current.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
        Divider()
        InfoRow(icon: "applewatch",
                label: "Source",
                value: current.sentFromWatch ? "Garmin FR255" : "iPhone")
    }
    .padding(16)
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14))
}
```

Remplacer `InfoRow` :

```swift
struct InfoRow: View {
    let icon:  String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.orange)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
```

- [ ] **Step 2 : Build + run**

`Cmd+R`. Vérifier : header card avec identité + score côte à côte + barre de progression, dots numérotés, fond adaptatif.

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Views/SessionDetailView.swift
git commit -m "feat: redesign SessionDetailView with unified header card"
```

---

## Task 7 : ManualSessionView + EditSessionView — Fond adaptatif

**Files:**
- Modify: `ios-app/BasketTrainer/Views/ManualSessionView.swift`
- Modify: `ios-app/BasketTrainer/Views/EditSessionView.swift`

- [ ] **Step 1 : ManualSessionView — fond + DatePicker + couleurs**

Dans `ManualSessionView.body`, remplacer `Color.black.ignoresSafeArea()` par `Color(.systemGroupedBackground).ignoresSafeArea()`.

Dans `datePicker`, supprimer `.colorScheme(.dark)` :

```swift
private var datePicker: some View {
    VStack(alignment: .leading, spacing: 14) {
        SectionLabel(title: "Date", icon: "calendar")
        DatePicker("", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

Dans `simpleForm`, remplacer le background du stepper :
```swift
// Avant
.background(Color.white.opacity(0.06))
// Après
.background(Color(.systemBackground))
```

Dans `templateSection`, remplacer les backgrounds :
```swift
// Toggle container
.background(Color(.systemBackground))
// TextField
.background(Color(.systemBackground))
```

Dans `saveButton`, remplacer `.foregroundStyle(.black)` par `.foregroundStyle(.white)` (meilleur contraste sur orange en light mode).

Dans `complexForm`, le bouton "Ajouter une série" :
```swift
// Avant
.background(Color.orange.opacity(0.1))
// Après
.background(Color.orange.opacity(0.15))
```

Dans `SeriesEditorRow`, remplacer `.background(Color.white.opacity(0.06))` par `.background(Color(.systemBackground))`. Remplacer les `.background(Color.white.opacity(0.1))` des chips exercice/tirs par `.background(Color(.secondarySystemBackground))`.

- [ ] **Step 2 : EditSessionView — fond + DatePicker + couleurs**

Dans `EditSessionView.body`, remplacer `Color.black.ignoresSafeArea()` par `Color(.systemGroupedBackground).ignoresSafeArea()`.

Dans `simpleEditor`, remplacer les `.background(Color.white.opacity(0.06))` par `.background(Color(.systemBackground))`.

Dans `complexEditor`, remplacer les `.background(Color.white.opacity(0.06))` par `.background(Color(.systemBackground))`.

Dans `datePicker`, supprimer `.colorScheme(.dark)` et remplacer background :
```swift
.background(Color(.systemBackground))
```

Dans `saveButton`, remplacer `.foregroundStyle(.black)` par `.foregroundStyle(.white)`.

- [ ] **Step 3 : Build + run**

`Cmd+R`. Vérifier les deux views en sheet : fond gris clair adaptatif, DatePicker en mode natif, champs lisibles.

- [ ] **Step 4 : Commit**

```bash
git add ios-app/BasketTrainer/Views/ManualSessionView.swift ios-app/BasketTrainer/Views/EditSessionView.swift
git commit -m "feat: redesign ManualSessionView and EditSessionView with adaptive colors"
```

---

## Task 8 : WorkoutConfigView + TemplatesView — Fond adaptatif

**Files:**
- Modify: `ios-app/BasketTrainer/Views/WorkoutConfigView.swift`
- Modify: `ios-app/BasketTrainer/Views/TemplatesView.swift`

- [ ] **Step 1 : WorkoutConfigView — fond + statut connexion + hint**

Remplacer tout `WorkoutConfigView` :

```swift
struct WorkoutConfigView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var garmin: GarminManager

    @State private var selectedExercise: ExerciseType = .freethrow
    @State private var shotCount: Int = 10
    @State private var didSend = false

    private let shotOptions = [5, 10, 15, 20, 25, 30]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        sectionExercise
                        sectionShotCount
                        connectionStatus
                        sendButton
                        if didSend { sentConfirmation }
                        hintText
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Envoyer à la montre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }

    private var sectionExercise: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Exercice", icon: "figure.basketball")
            VStack(spacing: 8) {
                ForEach(ExerciseType.allCases) { exercise in
                    ExerciseOptionRow(exercise: exercise, isSelected: selectedExercise == exercise)
                        .onTapGesture { selectedExercise = exercise }
                }
            }
        }
    }

    private var sectionShotCount: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Nombre de tirs", icon: "basketball")
            HStack(spacing: 10) {
                ForEach(shotOptions, id: \.self) { n in
                    ShotCountChip(count: n, isSelected: shotCount == n)
                        .onTapGesture { shotCount = n }
                }
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(garmin.lastSyncDate != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Forerunner 255")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let last = garmin.lastSyncDate {
                    Text("Synchro \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Aucune synchro récente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sendButton: some View {
        Button {
            withAnimation { didSend = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { didSend = false }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch")
                Text("Envoyer sur la montre")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var sentConfirmation: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Envoyé ! Lance l'app sur ta montre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var hintText: some View {
        Text("Ou lancez directement depuis la montre — les données seront synchronisées automatiquement.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}
```

- [ ] **Step 2 : TemplatesView + TemplateCard — fond adaptatif + bordure orange**

Dans `TemplatesView`, remplacer le `.background` du container :
```swift
// Avant
.background(Color.white.opacity(0.04))
// Après
.background(Color(.secondarySystemBackground))
```

Remplacer `TemplateCard` :

```swift
struct TemplateCard: View {
    let template:       ComplexTemplate
    let onLaunchManual: () -> Void
    let onLaunchGuided: () -> Void
    let onDelete:       () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(template.series.count) série\(template.series.count > 1 ? "s" : "") · \(template.series.reduce(0) { $0 + $1.totalShots }) tirs total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(template.series.indices, id: \.self) { idx in
                    let s = template.series[idx]
                    VStack(spacing: 2) {
                        Text(s.exerciseType.emoji).font(.caption)
                        Text("×\(s.totalShots)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if idx < template.series.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onLaunchManual) {
                    Label("Saisir", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button(action: onLaunchGuided) {
                    Label("Guider la montre", systemImage: "applewatch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert("Supprimer ce template ?", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive, action: onDelete)
            Button("Annuler", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 3 : Build + run complet**

`Cmd+R`. Vérifier tous les écrans en light mode (forcer via simulateur : Features → Toggle Appearance). Puis vérifier en dark mode. Vérifier WorkoutConfigView depuis HomeView (bouton CTA → si WorkoutConfigView est accessible).

- [ ] **Step 4 : Commit final**

```bash
git add ios-app/BasketTrainer/Views/WorkoutConfigView.swift ios-app/BasketTrainer/Views/TemplatesView.swift
git commit -m "feat: redesign WorkoutConfigView and TemplatesView with adaptive colors"
```

---

## Vérification finale

- [ ] Passer l'app en **light mode** (simulateur : Features → Toggle Appearance) — vérifier tous les écrans
- [ ] Passer en **dark mode** — vérifier que les couleurs sont correctes (pas de blanc sur blanc, pas de noir sur noir)
- [ ] Vérifier que le swipe to delete fonctionne dans HistoryView
- [ ] Vérifier que les templates en scroll horizontal s'affichent dans HomeView
- [ ] Vérifier que la recherche fonctionne dans HistoryView
- [ ] Vérifier que les chips de filtre Tous/Lancer Franc/3 Points/Mi-distance filtrent correctement
