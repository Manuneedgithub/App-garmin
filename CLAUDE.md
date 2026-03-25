# Basket Trainer — Contexte projet pour Claude

## Vue d'ensemble
Application de suivi d'entraînement basketball en deux parties :
- **App Garmin** (Monkey C / Connect IQ) → Forerunner 255 — **TERMINÉE ET FONCTIONNELLE**
- **App iPhone** (Swift / SwiftUI) → iOS 16+ — **À FINALISER sur Mac**

---

## Partie Garmin — État : ✅ Fonctionnelle

### Ce qui fonctionne
- Menu de sélection d'exercice (9 types : Lancer Franc, 3pts Centre/45°/Coin, Mi-distance)
- Menu de sélection du nombre de tirs (5, 10, 15, 20, 25, 30)
- Écran de tracking tir par tir :
  - Bouton HAUT = Réussi ✅
  - Bouton BAS = Raté ❌
  - Compteur "X / Y" + pourcentage + points colorés (vert/rouge)
- Écran de résumé final avec barre de performance
- Envoi des données vers l'iPhone via `Communications.transmit()` (fonctionne sur vraie montre, popup ADB normale en simulateur)

### Fichiers Garmin
```
garmin-app/
├── manifest.xml              UUID: a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a
├── monkey.jungle
├── .vscode/
│   ├── settings.json         typeCheckLevel: Informative
│   └── launch.json           config debug FR255
├── source/
│   ├── BasketApp.mc          point d'entrée
│   ├── ExerciseMenu.mc       constantes EX_* + getExerciseName() + menu
│   ├── ShotCountMenu.mc      menu nb de tirs
│   ├── WorkoutSession.mc     modèle de données + toDictionary()
│   ├── WorkoutView.mc        écran tracking + WorkoutDelegate
│   └── SummaryView.mc        écran résumé + envoi iPhone
└── resources/
    ├── strings/strings.xml
    └── drawables/
        ├── drawables.xml     référence LauncherIcon
        └── launcher_icon.png  40x40px orange
```

### Points techniques importants Garmin
- SDK version : **9.1.0** (`connectiq-sdk-win-9.1.0-2026-03-09`)
- Clé développeur : `garmin-app/developer_key` (ne pas committer)
- Build : `Ctrl+Shift+P` → "Monkey C: Build for Device"
- Simulateur : lancer `simulator.exe` puis `run-simulator.ps1` (PowerShell)
- `getInitialView()` doit retourner `[WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates]`
- Les `MenuItem` utilisent `null` comme dernier paramètre (pas `{}`)
- `getExerciseName()` est une fonction globale dans ExerciseMenu.mc
- `System.getDeviceStatus()` n'existe pas → on laisse `transmit()` échouer silencieusement
- Warning Dictionary/transmit : inoffensif à l'exécution, lié au typecheck strict

---

## Partie iPhone — État : 📁 Fichiers créés, à intégrer dans Xcode

### Fichiers Swift existants
```
ios-app/BasketTrainer/
├── BasketTrainerApp.swift        @main, setup Garmin + apparence
├── Models/
│   ├── Models.swift              ExerciseType, WorkoutSession, ExerciseStats
│   └── SessionStore.swift        persistence UserDefaults, @Published
├── Managers/
│   └── GarminManager.swift       pont Bluetooth (mode mock actif)
└── Views/
    ├── ContentView.swift          TabView : Accueil / Historique / Stats
    ├── HomeView.swift             dashboard + séances récentes + bouton nouvel entraînement
    ├── WorkoutConfigView.swift    config exercice + nb tirs + envoi montre
    ├── HistoryView.swift          liste filtrables, swipe to delete, groupé par date
    ├── SessionDetailView.swift    détail tir par tir (dots verts/rouges)
    └── StatsView.swift            graphique progression + stats par exercice (Swift Charts)
```

### Ce qu'il reste à faire sur Mac

#### 1. Créer le projet Xcode
```
Xcode → New Project → iOS → App
- Product Name: BasketTrainer
- Bundle ID: com.tonnom.baskettrainer
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: iOS 16
```
Puis copier tous les fichiers Swift du dossier `ios-app/BasketTrainer/` dans le projet.

#### 2. Intégrer le SDK Garmin Connect IQ (iOS)
- Télécharger ConnectIQ.xcframework sur developer.garmin.com
- L'ajouter dans Xcode → Target → General → Frameworks (Embed & Sign)
- Ajouter dans Info.plist :
  ```xml
  LSApplicationQueriesSchemes → ["com.garmin.connect.mobile"]
  CFBundleURLTypes → scheme "baskettrainer"
  ```
- Dans `GarminManager.swift` : décommenter les blocs `// [SDK]`

#### 3. Tester sans SDK Garmin (mode mock)
Dans `HomeView.swift`, un bouton debug peut appeler `garmin.addMockSession()` pour tester l'UI sans vraie montre.

### Design iPhone
- Thème : dark mode forcé, accent orange (#FF6600)
- 3 onglets : Accueil / Historique / Stats
- Swift Charts pour le graphique de progression (iOS 16+)
- Persistence : UserDefaults via JSONEncoder/Decoder

### Communication montre → iPhone
```
WorkoutSession.toDictionary() → Communications.transmit() → GarminManager.handleIncomingMessage() → SessionStore.add()
```
Données envoyées : `exerciseId`, `exerciseName`, `totalShots`, `madeShots`, `percentage`, `startTime`, `results`

---

## UUID de l'app (à conserver impérativement)
```
a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a
```
Ce même UUID doit être dans `manifest.xml` ET dans `GarminManager.swift`.

---

## Commandes utiles

### Garmin (Windows)
```powershell
# Build
Ctrl+Shift+P → "Monkey C: Build for Device"

# Simulateur
Start-Process "...\simulator.exe"
& "...\shell.exe" "C:\...\BasketApp\garminapp.prg"

# Script tout-en-un
.\run-simulator.ps1
```

### iPhone (Mac)
```bash
# Ouvrir dans Xcode
open ios-app/BasketTrainer.xcodeproj

# Build + run iPhone
Cmd+R
```
