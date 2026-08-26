# Android MVP Core — Design

## Contexte

Basket Trainer existe aujourd'hui sur deux plateformes : l'app Garmin (Monkey C, terminée) et l'app iPhone (Swift/SwiftUI, en cours de finalisation). Ce document cadre le premier sous-projet d'un portage Android natif (Kotlin + Jetpack Compose), qui vivra en parallèle dans le même repo (`android-app/`, aux côtés de `garmin-app/` et `ios-app/`).

Le portage complet est trop large pour un seul spec. Il est découpé en 4 sous-projets indépendants :

1. **MVP core** (ce document) — squelette, modèles, persistance, réception d'une séance depuis la montre, Accueil + Historique
2. **Terrain / spots** — portage de `CourtView` (repères draggables) + spots personnalisés + sync vers la montre
3. **Stats** — portage de `StatsView` (graphiques, heatmap, records, fatigue)
4. **Séances complexes** — saisie manuelle, édition, slots montre (`SlotsView`, `WorkoutConfigView`, `ManualSessionView`, `EditSessionView`)

Chaque sous-projet suivant aura son propre cycle spec → plan → implémentation.

## Portée de ce sous-projet

**Inclus :**
- Squelette de projet Android Studio
- Modèles de données (portage 1:1 depuis `ios-app/BasketTrainer/Models/Models.swift`)
- Persistance (équivalent de `SessionStore`)
- Intégration du Connect IQ Mobile SDK Android pour recevoir une séance envoyée par la montre
- Écrans Accueil + Historique (Jetpack Compose)

**Hors scope (sous-projets suivants) :** Terrain/spots personnalisés, Stats/graphiques, séances complexes, slots montre, saisie manuelle, édition de séance.

## Décisions de cadrage

- **Stack** : Kotlin natif + Jetpack Compose (pas de Kotlin Multiplatform ni Flutter — chaque plateforme reste native et indépendante, comme aujourd'hui entre Garmin et iOS)
- **Package** : `com.tonnom.baskettrainer` (identique au bundle ID iOS)
- **minSdk** : 26 (Android 8.0)
- **Test** : téléphone Android physique disponible, connexion réelle à la Forerunner 255 dès ce sous-projet (pas de mode mock requis pour valider le flux Garmin)
- **UUID de l'app Garmin** : `a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a` — identique à `manifest.xml` et `GarminManager.swift`, à conserver impérativement

## Architecture

Structure de dossiers, miroir de `ios-app/BasketTrainer/` :

```
android-app/
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/tonnom/baskettrainer/
│       │   ├── MainActivity.kt
│       │   ├── BasketTrainerApp.kt        (Application, init GarminManager)
│       │   ├── model/
│       │   │   └── Models.kt              (ExerciseType, ShotType, WorkoutSession, ShotSeries, CustomSpot, SpotPosition, ExerciseStats, SpotStats)
│       │   ├── data/
│       │   │   └── SessionRepository.kt   (persistance DataStore, StateFlow<List<WorkoutSession>>)
│       │   ├── garmin/
│       │   │   └── GarminManager.kt       (intégration Connect IQ SDK)
│       │   └── ui/
│       │       ├── HomeScreen.kt
│       │       ├── HistoryScreen.kt
│       │       ├── components/            (SessionRow, MiniStatCard, ...)
│       │       └── theme/                 (dark mode forcé, accent orange #FF6600 — parité avec iOS)
```

## Couche données

**`Models.kt`** — portage 1:1 de `Models.swift`. `ExerciseType` conserve les ordinaux 0-15, y compris la plage réservée 11-15 pour les spots personnalisés (même si leur écran de création arrive au sous-projet 2) : sans ça, une séance envoyée par la montre référençant un spot custom serait mal décodée dès ce MVP. `WorkoutSession`, `ShotSeries`, `ShotType`, `CustomSpot`, `SpotPosition` suivent la même structure que côté iOS, avec `kotlinx.serialization` à la place de `Codable`.

**`SessionRepository`** — objet singleton (équivalent de `SessionStore.shared`), expose `StateFlow<List<WorkoutSession>>`, persisté via Jetpack DataStore (Preferences), séances encodées en JSON — même principe que UserDefaults + JSONEncoder côté iOS. Pour ce sous-projet : uniquement lecture, `add()` et `delete()`. Pas de slots montre, positions de spots ni spots personnalisés (sous-projets 2 et 4).

## Intégration Garmin

`GarminManager` utilise le Connect IQ Mobile SDK Android (à télécharger depuis developer.garmin.com et ajouter en dépendance Gradle — équivalent du `ConnectIQ.xcframework` déjà documenté dans `CLAUDE.md` pour iOS).

Différence notable avec iOS : le SDK Android découvre les appareils via Garmin Connect Mobile (`sdk.knownDevices`), sans le contournement CoreBluetooth qu'il a fallu faire côté iOS (UUID de peripheral hardcodé car `showDeviceSelection()` ne fonctionne pas avec GCM 5.23+ — cf. mémoire du projet). Ce hack n'a donc pas d'équivalent à porter.

Flux, identique côté logique à iOS :
1. Device connecté → `register(app, listener)`
2. Réception d'un message → `parseAndStore()` mappe les mêmes champs que `GarminManager.swift` : `exerciseId`, `totalShots`, `madeShots`, `startTime`, `duration`, `results`, `targetMade`, `shotTypeId`
3. Séance ajoutée au `SessionRepository`

**Spécificité Android** : sur API 31+, les permissions Bluetooth runtime (`BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN`) doivent être demandées explicitement à l'utilisateur au lancement de l'app — pas d'équivalent direct côté iOS (une simple clé Info.plist y suffit).

## UI

- **`MainActivity`** — activité unique, `NavHost` Compose avec barre de navigation basse à 2 onglets : Accueil, Historique (l'onglet Stats arrive au sous-projet 3).
- **`HomeScreen`** — portage direct de `HomeView.swift` : ligne de statut montre (connectée/non connectée + bouton "Connecter"), stats rapides (séances / tirs / réussite), liste des séances récentes. Le bouton "Nouvel entraînement" est omis pour ce sous-projet (saisie manuelle → sous-projet 4).
- **`HistoryScreen`** — portage de `HistoryView.swift` : liste groupée par date, swipe-to-delete, filtre par type d'exercice (types intégrés uniquement — pas de spots custom nommés tant que le sous-projet 2 n'existe pas).

## Gestion d'erreurs

- Échec de décodage JSON au chargement → repli sur liste vide (même logique que le `try?` côté iOS)
- Garmin Connect Mobile absent du téléphone → message explicite sur l'écran Accueil plutôt qu'un crash
- Permission Bluetooth refusée → message persistant avec bouton pour redemander, plutôt qu'une boucle de popup système

## Tests

Comme côté iOS (aucune infra de tests automatisés dans le repo), vérification manuelle : lancer l'app sur le téléphone Android physique, connecter la montre, faire une séance de tirs sur la Forerunner 255, vérifier qu'elle apparaît dans l'Historique.
