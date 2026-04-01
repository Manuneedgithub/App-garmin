# Mode Objectif — Basket Trainer

**Date :** 2026-04-01  
**Scope :** App Garmin (Monkey C) + ajustement modèles iPhone (Swift)

---

## Vue d'ensemble

Nouveau mode "Objectif" sur la montre Garmin Forerunner 255. Au lieu de tirer un nombre fixe de fois, l'utilisateur définit un **nombre de paniers à rentrer**. La session s'arrête automatiquement quand l'objectif est atteint. Le ratio mis/total est conservé pour les stats.

Deux sous-modes :
- **Objectif simple** : un exercice, un objectif de paniers
- **Objectif complexe** : plusieurs exercices enchaînés (via template iPhone), chacun avec son propre objectif de paniers

Côté iPhone : aucune modification de la réception des données (même format qu'aujourd'hui). Seul ajout : le champ `targetMade` dans les modèles de template.

---

## Garmin — Modifications

### 1. Menu principal (`BasketApp.mc` + nouveau `MainMenu.mc`)

Remplacement du menu actuel (exercice direct) par un menu à 3 entrées :

```
1. Tirs libres     ← mode actuel inchangé
2. Objectif simple ← nouveau
3. Objectif complexe ← nouveau (reçoit config depuis iPhone via guided session)
```

### 2. Nouveau `GoalMenu.mc` — Sélection de l'objectif

Affiché après la sélection de l'exercice (mode simple) ou au démarrage d'une série (mode complexe).

- Chips rapides : 5, 10, 15, 20, 25, 30
- Bouton HAUT (+1) / BAS (-1) pour ajustement fin
- Bouton SELECT pour valider
- Valeur initiale : 10

### 3. Nouveau `GoalSession.mc` — Modèle de données

```monkeyc
class GoalSession {
    var exerciseId   as Number;
    var exerciseName as String;
    var targetMade   as Number;  // objectif paniers
    var madeShots    as Number;  // paniers réussis
    var totalShots   as Number;  // tirs au total
    var results      as Array;   // [true/false] par tir
    var startTime    as Number;  // timestamp Unix
}
```

Méthode `toDictionary()` : même format que `WorkoutSession.toDictionary()` + champ `targetMade`.

### 4. Nouveau `GoalView.mc` — Écran de tracking

```
┌──────────────────────────┐
│      Lancer Franc        │  petit, gris
│   Objectif : 10 🏀       │  petit, blanc
│                          │
│       5 / 8              │  grand : mis / tirs
│                          │
│  ████████░░░░░░░░░░░░    │  barre : progression vers objectif
│                          │
│  ▲ Réussi   ▼ Raté       │  gris petit
└──────────────────────────┘
```

- Barre de progression : `madeShots / targetMade` (pas `totalShots`)
- Couleur barre : orange → vert quand objectif atteint
- Quand `madeShots == targetMade` → transition automatique vers `GoalSummaryView`

### 5. Nouveau `GoalSummaryView.mc` — Résumé final

Identique à `SummaryView.mc` existant, avec :
- Ligne supplémentaire : "Objectif : X paniers ✓"
- Bouton SELECT → envoie données + retour menu principal
- Bouton BACK → retour menu sans envoyer

### 6. Mode complexe — `GoalComplexSession.mc`

Utilisé quand la montre reçoit un template depuis l'iPhone (guided session existant).

- Chaque `TemplateSeries` contient maintenant `targetMade`
- Quand `madeShots == targetMade` pour la série courante → passe automatiquement à la série suivante (sans validation manuelle)
- Affiche en haut : "Série X / N" + exercice suivant

---

## iPhone — Modifications

### Modèles (`Models.swift`)

Ajout de `targetMade: Int?` dans `TemplateSeries` :

```swift
struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int        // nombre de tirs max (indicatif)
    var targetMade: Int?       // objectif paniers (nil = mode tirs libres)
}
```

Ajout de `targetMade: Int?` dans `ShotSeries` (pour affichage dans `SessionDetailView`).

### `ManualSessionView.swift` — UI template

Dans `SeriesEditorRow`, ajout d'un stepper optionnel "Objectif paniers" quand `targetMade` est activé (toggle simple).

### `SessionDetailView.swift`

Si `targetMade` non nil : afficher "Objectif : X paniers" dans les stats de la série.

### Communication montre → iPhone

Format `toDictionary()` enrichi avec `targetMade` :

```
{
  exerciseId:   Int,
  exerciseName: String,
  totalShots:   Int,
  madeShots:    Int,
  percentage:   Int,
  startTime:    Int,
  duration:     Int,
  results:      [Bool],
  targetMade:   Int       ← nouveau, optionnel
}
```

`parseAndStore()` dans `GarminManager` lit `targetMade` si présent.

---

## Fichiers à créer (Garmin)

| Fichier | Rôle |
|---------|------|
| `MainMenu.mc` | Nouveau menu principal à 3 entrées |
| `GoalMenu.mc` | Sélection de l'objectif (chips + boutons) |
| `GoalSession.mc` | Modèle de données session objectif |
| `GoalView.mc` | Écran de tracking avec barre progression |
| `GoalSummaryView.mc` | Résumé final + envoi iPhone |
| `GoalComplexSession.mc` | Gestion enchaînement séries avec objectifs |

## Fichiers à modifier (Garmin)

| Fichier | Modification |
|---------|-------------|
| `BasketApp.mc` | Pointer vers `MainMenu` au lieu de `ExerciseMenu` |
| `ExerciseMenu.mc` | Inchangé (réutilisé par les deux modes) |

## Fichiers à modifier (iPhone)

| Fichier | Modification |
|---------|-------------|
| `Models.swift` | Ajout `targetMade` dans `TemplateSeries` et `ShotSeries` |
| `GarminManager.swift` | Lire `targetMade` dans `parseAndStore()` |
| `ManualSessionView.swift` | Toggle + stepper objectif dans `SeriesEditorRow` |
| `SessionDetailView.swift` | Afficher objectif si présent |

---

## Ce qui ne change pas

- Format de réception des messages iPhone inchangé (rétrocompatible — `targetMade` est optionnel)
- Mode "Tirs libres" existant inchangé
- `WorkoutSession`, `SessionStore`, `HistoryView`, `StatsView` inchangés
