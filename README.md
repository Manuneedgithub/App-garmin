# Basket Trainer

Application de suivi d'entraînement au tir au basket, en trois parties :

- ⌚ **App Garmin** (Monkey C) — tourne sur la montre, enregistre les tirs pendant l'entraînement
- 📱 **App iPhone** (SwiftUI) — reçoit les séances, historique, statistiques, configuration
- 🤖 **App Android** (Kotlin / Jetpack Compose) — équivalent Android, en cours de portage

La montre fait le tracking pendant que tu es sur le terrain (mains prises par le ballon, pas envie de sortir le téléphone). Le téléphone récupère les séances automatiquement en Bluetooth et sert d'historique, de tableau de stats et d'écran de configuration.

---

## Sommaire

- [Comment ça marche](#comment-ça-marche)
- [Fonctionnalités](#fonctionnalités)
- [Structure du repo](#structure-du-repo)
- [Installation](#installation)
  - [1. Montre Garmin](#1-montre-garmin-monkey-c)
  - [2. iPhone](#2-iphone-swiftui)
  - [3. Android](#3-android-kotlin--jetpack-compose)
  - [Faire communiquer montre et téléphone](#faire-communiquer-montre-et-téléphone)
- [État d'avancement](#état-davancement)
- [Dépannage](#dépannage)

---

## Comment ça marche

```
┌─────────────────┐   Bluetooth (Connect IQ SDK)   ┌──────────────────────┐
│  Montre Garmin   │ ──────────────────────────────▶│  Téléphone (iPhone /  │
│  (Monkey C)      │   Communications.transmit()    │  Android)             │
│                   │◀────────────────────────────── │                       │
│ - Choix exercice │   Envoi routine / slot / spots │ - Historique          │
│ - Comptage tirs  │                                 │ - Statistiques        │
│ - File d'attente │                                 │ - Terrain interactif  │
│   hors-ligne     │                                 │ - Config montre       │
└─────────────────┘                                 └──────────────────────┘
```

1. Sur la montre, tu choisis un exercice (ou une routine/slot préconfiguré) et tu tires. Bouton **Haut** = réussi, bouton **Bas** = raté.
2. À la fin de la séance, la montre transmet directement les données au téléphone via le SDK Connect IQ (Bluetooth, silencieux, sans notification qui s'affiche).
3. Si le téléphone n'est pas joignable (app fermée, hors de portée), la séance est stockée dans une file d'attente sur la montre (`PendingQueue`) et renvoyée automatiquement dès que l'app téléphone se relance et réveille la montre.
4. Le téléphone décode le message reçu, l'ajoute à l'historique local, et met à jour les statistiques.
5. Dans l'autre sens, le téléphone peut pousser vers la montre : la liste des spots personnalisés, ou des routines d'entraînement complètes (slots) à exécuter de façon autonome sur le terrain, sans avoir besoin du téléphone à ce moment-là.

Aucun serveur, aucun compte, aucune synchronisation cloud : tout reste en local entre la montre et le téléphone, connectés via l'app **Garmin Connect Mobile** (qui doit être installée et faire tourner le pont Bluetooth en arrière-plan).

**UUID de l'app** (doit être identique sur la montre et sur chaque app téléphone — ne jamais changer) :
```
a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a
```

---

## Fonctionnalités

### Sur la montre

- **11 zones de tir intégrées** : lancer franc, 3 points (centre / 45° droite / 45° gauche / coin droite / coin gauche), mi-distance (centre / droite / gauche), plus 2 exercices technique (flotteur, form shot side-to-side)
- **Jusqu'à 5 spots personnalisés** créés depuis le téléphone et synchronisés automatiquement dans le menu de la montre
- **Type de tir** : Catch & Shoot / Avec dribble / À l'arrêt — pour distinguer des séances au même endroit mais pas au même geste
- **Deux modes de séance** :
  - *Tirs fixes* : un nombre de tirs défini à l'avance (5 à 30)
  - *Objectif* : la séance s'arrête dès qu'un nombre de paniers donné est atteint (simple ou en plusieurs exercices enchaînés)
- **Slots d'entraînement** : jusqu'à 5 routines complètes (plusieurs séries, exercices et objectifs enchaînés) configurées depuis le téléphone une fois, puis lancées directement depuis la montre sans avoir besoin du téléphone sur le terrain
- **File d'attente hors-ligne** : aucune séance perdue si le téléphone n'est pas à portée au moment de la fin d'entraînement

### Sur iPhone

- **Accueil** : statut de connexion à la montre, stats rapides, séances récentes
- **Historique** filtrable, séances groupées par date, détail tir par tir
- **Statistiques** : graphique de progression, heatmap d'assiduité, records personnels, résistance à la fatigue (1ère vs 2ème moitié de séance), stats par exercice
- **Terrain interactif** : carte du terrain (vraie photo) avec le % de réussite affiché par zone, repères déplaçables à la main pour s'aligner sur la photo
- **Spots personnalisés** : création/édition/suppression (jusqu'à 5), avec envoi automatique vers la montre
- **Configuration des slots montre** et des routines guidées
- **Saisie manuelle** d'une séance (sans passer par la montre) et édition d'une séance existante

### Sur Android

Portage en cours (voir [État d'avancement](#état-davancement)). La v1 disponible couvre :
- Connexion à la montre et réception d'une séance en direct
- Persistance locale des séances
- Écran Accueil (statut montre, stats rapides, séances récentes) et Historique (groupé par date, suppression avec confirmation)

Le Terrain, les Statistiques, les spots personnalisés et les séances complexes/slots arrivent dans de prochains sous-projets — voir `docs/superpowers/specs/2026-08-26-android-mvp-core-design.md` pour le détail du découpage prévu.

---

## Structure du repo

```
App garmin/
├── garmin-app/                        App montre (Monkey C / Connect IQ)
│   ├── manifest.xml                     UUID app, appareils ciblés (FR255 et variantes)
│   ├── monkey.jungle                    Fichier de build
│   ├── developer_key                    Clé de signature (ne pas committer)
│   ├── source/
│   │   ├── BasketApp.mc                 Point d'entrée
│   │   ├── MainMenu.mc                  Menu principal (exercice / slot / objectif)
│   │   ├── ExerciseMenu.mc              Choix de la zone de tir
│   │   ├── ShotCountMenu.mc             Choix du nombre de tirs
│   │   ├── ShotTypeMenu.mc              Choix du type de tir
│   │   ├── GoalMenu.mc / GoalSession.mc / GoalView.mc / GoalSummaryView.mc
│   │   │                                 Mode "Objectif" (nombre de paniers)
│   │   ├── SlotMenu.mc / RoutineRunner.mc / SessionAccumulator.mc / SeriesDoneView.mc
│   │   │                                 Slots d'entraînement (routines multi-séries)
│   │   ├── WorkoutSession.mc            Modèle de données d'une séance simple
│   │   ├── WorkoutView.mc / SummaryView.mc
│   │   │                                 Écran de tracking + écran de résumé
│   │   ├── PendingQueue.mc / SyncManager.mc / TransmitDelegate.mc
│   │   │                                 File d'attente + sync hors-ligne vers le téléphone
│   │   └── resources/                   Strings, icônes
│   └── bin/                             Sorties de build (générées, à ignorer)
│
├── ios-app/                           App iPhone (Swift / SwiftUI)
│   ├── BasketTrainer.xcodeproj          Projet Xcode
│   ├── ConnectIQ.xcframework            SDK Garmin (téléchargé à part, voir installation)
│   └── BasketTrainer/
│       ├── BasketTrainerApp.swift       Point d'entrée
│       ├── Models/
│       │   ├── Models.swift               ExerciseType, WorkoutSession, CustomSpot, stats...
│       │   └── SessionStore.swift         Persistence (UserDefaults) + logique métier
│       ├── Managers/
│       │   └── GarminManager.swift        Pont Bluetooth avec la montre (Connect IQ SDK)
│       └── Views/
│           ├── ContentView.swift          Navigation par onglets
│           ├── HomeView.swift             Accueil
│           ├── HistoryView.swift / SessionDetailView.swift / EditSessionView.swift
│           ├── StatsView.swift            Statistiques + graphiques
│           ├── CourtView.swift / SpotDetailView.swift / CustomSpotEditorView.swift
│           │                               Terrain interactif + spots personnalisés
│           ├── WorkoutConfigView.swift / ManualSessionView.swift
│           └── SlotsView.swift            Configuration des slots montre
│
├── android-app/                       App Android (Kotlin / Jetpack Compose)
│   └── app/src/main/java/com/tonnom/baskettrainer/
│       ├── BasketTrainerApp.kt           Point d'entrée (Application)
│       ├── MainActivity.kt               Navigation (bottom bar)
│       ├── model/Models.kt               Portage des modèles de données
│       ├── data/                         Persistance (DataStore) + codec JSON
│       ├── garmin/                       Intégration Connect IQ SDK Android
│       └── ui/                           Écrans Compose (Accueil, Historique)
│
├── docs/superpowers/
│   ├── specs/                          Design specs de chaque fonctionnalité (une par feature)
│   └── plans/                          Plans d'implémentation détaillés correspondants
│
├── CLAUDE.md                          Contexte projet condensé (pour Claude Code)
├── SETUP.md                           Guide de setup pas-à-pas (Garmin + iPhone)
└── README.md                          Ce fichier
```

---

## Installation

Chaque plateforme est indépendante — tu n'as besoin d'installer que celles qui t'intéressent. Pour que la communication montre ↔ téléphone fonctionne, il te faut au minimum la montre **et** un des deux téléphones.

### 1. Montre Garmin (Monkey C)

**Prérequis :** un compte développeur Garmin (gratuit) et le SDK Connect IQ.

1. Télécharge le [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) via le SDK Manager.
2. Dans l'onglet **Devices**, installe la Forerunner 255 (et variantes 255s / 255m / 255sm si besoin).
3. Installe l'extension VS Code **Monkey C** (éditeur : Garmin) — elle détecte le SDK automatiquement.
4. Ouvre le dossier `garmin-app/` dans VS Code. Le fichier `monkey.jungle` est le point d'entrée du build.
5. Génère ta clé de développeur si tu n'en as pas : `Ctrl+Shift+P` → **Monkey C: Generate Developer Key**.
6. Compile et teste en simulateur : `Ctrl+Shift+P` → **Monkey C: Run in Simulator** → sélectionne Forerunner 255.
7. Pour déployer sur une vraie montre : active le mode développeur sur la montre (Paramètres → Système → À propos → tapoter 7 fois sur "Logiciel"), connecte-la en USB, puis `Ctrl+Shift+P` → **Monkey C: Deploy to Device**.
8. Enregistre l'app sur [apps.garmin.com/developer](https://apps.garmin.com/developer) avec l'UUID `a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a` (déjà dans `manifest.xml`) — nécessaire pour que le SDK téléphone reconnaisse l'app.

### 2. iPhone (SwiftUI)

**Prérequis :** Xcode 15+, macOS Ventura minimum, un compte Apple Developer (le compte gratuit suffit pour tester sur ton propre iPhone).

1. Ouvre `ios-app/BasketTrainer.xcodeproj` dans Xcode.
2. Télécharge le **Connect IQ Mobile SDK pour iOS** sur [developer.garmin.com](https://developer.garmin.com/connect-iq/sdk/) et vérifie que `ConnectIQ.xcframework` est bien ajouté au projet (Target → General → Frameworks, Libraries, and Embedded Content, en **Embed & Sign**).
3. Vérifie que `Info.plist` contient :
   ```xml
   <key>LSApplicationQueriesSchemes</key>
   <array><string>com.garmin.connect.mobile</string></array>
   <key>CFBundleURLTypes</key>
   <array><dict><key>CFBundleURLSchemes</key>
     <array><string>baskettrainer</string></array>
   </dict></array>
   ```
4. Branche ton iPhone en USB, sélectionne-le comme destination dans Xcode, puis `Cmd+R`.
5. Au premier lancement : **Réglages → Général → VPN et gestion de l'appareil** sur l'iPhone → fais confiance au certificat développeur.

### 3. Android (Kotlin / Jetpack Compose)

**Prérequis :** Android Studio (ou le SDK Android en ligne de commande) et un téléphone Android avec l'app **Garmin Connect Mobile** installée.

1. Ouvre le dossier `android-app/` dans Android Studio — il détecte et synchronise le SDK Connect IQ automatiquement (dépendance Gradle publiée sur Maven Central, pas de téléchargement manuel nécessaire).
2. Si Android Studio ne trouve pas de SDK Android, laisse-le proposer d'en installer un (Setup Wizard), ou renseigne toi-même `android-app/local.properties` :
   ```properties
   sdk.dir=/chemin/vers/ton/Android/sdk
   ```
3. Build : `./gradlew assembleDebug` depuis `android-app/` (ou bouton ▶ Run dans Android Studio).
4. Installe sur un appareil physique connecté en USB (le débogage Bluetooth réel avec la montre nécessite un vrai téléphone, pas un émulateur) : `./gradlew installDebug`.

### Faire communiquer montre et téléphone

Quel que soit le téléphone utilisé :

1. Installe et connecte-toi à **Garmin Connect Mobile**, avec la montre appairée.
2. Lance l'app Basket Trainer (iPhone ou Android) — elle se connecte automatiquement à la montre déjà appairée.
3. Lance une séance sur la montre, tire, termine-la.
4. La séance apparaît automatiquement dans l'historique du téléphone, sans action supplémentaire.

Si le téléphone n'a pas de connexion au moment où la séance se termine sur la montre, elle est mise en attente côté montre et se synchronise automatiquement au prochain lancement de l'app téléphone.

---

## État d'avancement

| Plateforme | État | Détail |
|---|---|---|
| ⌚ Garmin (Monkey C) | ✅ Terminée et fonctionnelle | Toutes les fonctionnalités listées ci-dessus sont en place |
| 📱 iPhone (SwiftUI) | ✅ Fonctionnelle | Toutes les fonctionnalités listées ci-dessus sont en place |
| 🤖 Android (Kotlin/Compose) | 🚧 MVP core | Réception montre + persistance + Accueil/Historique. Reste à porter : Terrain/spots, Stats, séances complexes/slots (voir `docs/superpowers/plans/`) |

Chaque fonctionnalité de l'app a son propre document de conception dans `docs/superpowers/specs/` et son plan d'implémentation détaillé dans `docs/superpowers/plans/`, utile pour comprendre pourquoi telle décision a été prise avant de modifier le code correspondant.

---

## Dépannage

**Montre — "Cannot find symbol"** → vérifie que tous les fichiers `.mc` sont bien dans `garmin-app/source/`.

**Montre — "Device not found"** → lance d'abord le simulateur Connect IQ avant de builder.

**Le téléphone ne reçoit rien de la montre** → vérifie que Garmin Connect Mobile tourne bien en arrière-plan et que la montre est appairée (pas juste "à portée").

**Une séance manque à l'appel** → si le téléphone était injoignable au moment de la fin de séance, relance l'app téléphone : elle réveille la montre et déclenche l'envoi de la file d'attente (`PendingQueue`).

**Build iOS échoue sur `import Charts`** → Swift Charts nécessite iOS 16+ ; l'app cible déjà ce minimum, vérifie la version de déploiement du projet si l'erreur apparaît.

**Build Android échoue avec "SDK location not found"** → aucun SDK Android n'est configuré sur la machine ; ouvre le projet dans Android Studio pour qu'il t'en propose l'installation, ou renseigne `android-app/local.properties` manuellement.

**L'UUID ne correspond pas entre plateformes** → l'UUID `a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a` doit être identique dans `garmin-app/manifest.xml`, `ios-app/BasketTrainer/Managers/GarminManager.swift` et `android-app/.../garmin/GarminManager.kt` — ne jamais le régénérer, la reconnaissance entre montre et téléphone en dépend entièrement.
