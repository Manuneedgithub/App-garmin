# Basket Trainer — Guide de setup complet

---

## PARTIE 1 — App Garmin (Monkey C)

### 1.1 Installer le SDK Connect IQ

1. Va sur **developer.garmin.com/connect-iq/sdk/**
2. Clique **Download SDK**
3. Lance le SDK Manager qui s'ouvre
4. Dans l'onglet **Devices**, coche `Forerunner 255` → Install
5. Dans l'onglet **SDKs**, installe la version **4.1.7** ou plus récente

### 1.2 Installer l'extension VS Code (recommandé)

1. Ouvre VS Code
2. Extensions → cherche **Monkey C** (éditeur : Garmin)
3. Installer
4. L'extension détecte automatiquement le SDK

### 1.3 Créer le projet dans VS Code

1. `Ctrl+Shift+P` → **Monkey C: Build Current Project**
2. Ou ouvre directement le dossier `garmin-app/`
3. Le fichier `monkey.jungle` est le point d'entrée du build

### 1.4 Compiler et tester sur simulateur

```bash
# Dans le terminal VS Code, depuis garmin-app/
monkeyc -f monkey.jungle -o bin/basket.prg -d fr255 -y developer_key.der
```

Pour le `developer_key.der` :
- `Ctrl+Shift+P` → **Monkey C: Generate Developer Key**
- Ça crée automatiquement ta clé dans le dossier

**Sur simulateur :**
- `Ctrl+Shift+P` → **Monkey C: Run in Simulator**
- Sélectionne `Forerunner 255`

### 1.5 Déployer sur la vraie montre

1. Active le **mode développeur** sur ta FR255 :
   - Paramètres → Système → À propos → tappe 7 fois sur "Logiciel"
2. Connecte la montre en USB
3. `Ctrl+Shift+P` → **Monkey C: Deploy to Device**

### 1.6 Enregistrer ton app (pour la communication Bluetooth)

1. Va sur **apps.garmin.com/developer** → Create App
2. UUID : `a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a` (déjà dans manifest.xml)
3. Type : **Watch App**
4. Note le **Store App ID** — tu en auras besoin pour le SDK iOS

---

## PARTIE 2 — App iPhone (SwiftUI)

### 2.1 Prérequis

- **Xcode 15+** (App Store ou developer.apple.com)
- macOS Ventura minimum
- Un compte Apple Developer (gratuit suffit pour tester sur ton iPhone)

### 2.2 Créer le projet Xcode

1. Ouvre Xcode → **Create New Project**
2. Choisis **iOS → App**
3. Paramètres :
   - Product Name: `BasketTrainer`
   - Bundle ID: `com.tonnom.baskettrainer`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Crée le projet dans `ios-app/`
5. **Remplace** tous les fichiers `.swift` générés par ceux du dossier `BasketTrainer/`

### 2.3 Ajouter le SDK Garmin Connect IQ (iOS)

1. Va sur **developer.garmin.com/connect-iq/sdk/**
2. Télécharge **Connect IQ Mobile SDK for iOS**
3. Dans Xcode :
   - Sélectionne ton projet → Target → **General**
   - Fais glisser `ConnectIQ.xcframework` dans **Frameworks, Libraries, and Embedded Content**
   - Assure-toi que c'est en **Embed & Sign**

4. Dans `Info.plist`, ajoute :
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>com.garmin.connect.mobile</string>
</array>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>baskettrainer</string>
        </array>
    </dict>
</array>
```

5. Dans `GarminManager.swift`, **décommente les blocs `[SDK]`** et **supprime les blocs `[MOCK]`**

6. Modifie `BasketTrainerApp.swift` pour ajouter dans le `App struct` :
```swift
func application(_ app: UIApplication, open url: URL, options: ...) -> Bool {
    return ConnectIQ.sharedInstance().parseIncoming(url)
}
```

### 2.4 Tester sur ton iPhone

1. Branche ton iPhone en USB
2. Dans Xcode, sélectionne ton iPhone comme destination
3. `Cmd+R` pour builder et lancer
4. La première fois : **Réglages → VPN et gestion** → approuve le certificat développeur

---

## PARTIE 3 — Faire communiquer montre et iPhone

### Prérequis
- Garmin Connect installé sur l'iPhone
- La montre **appairée** à Garmin Connect
- Les deux apps lancées simultanément

### Comment ça marche
```
Montre → Garmin Connect (Bluetooth) → ConnectIQ Framework → Ton app iPhone
```

1. Lance **Basket Trainer** sur la montre
2. Lance **Basket Trainer** sur l'iPhone
3. Termine une séance sur la montre → "Sauvegarder"
4. La session apparaît automatiquement dans l'historique iPhone

---

## PARTIE 4 — Structure des fichiers

```
App garmin/
│
├── SETUP.md                        ← ce fichier
│
├── garmin-app/                     ← App Monkey C (montre)
│   ├── manifest.xml                  Configuration + UUID app
│   ├── monkey.jungle                 Fichier de build
│   ├── source/
│   │   ├── BasketApp.mc              Point d'entrée
│   │   ├── ExerciseMenu.mc           Menu choix exercice
│   │   ├── ShotCountMenu.mc          Menu nb de tirs
│   │   ├── WorkoutSession.mc         Modèle de données
│   │   ├── WorkoutView.mc            Écran tracking + delegate
│   │   └── SummaryView.mc            Écran résumé + delegate
│   └── resources/
│       ├── strings/strings.xml       Textes
│       └── drawables/drawables.xml   Polices/couleurs
│
└── ios-app/                        ← App Swift (iPhone)
    └── BasketTrainer/
        ├── BasketTrainerApp.swift    Point d'entrée SwiftUI
        ├── Models/
        │   ├── Models.swift          ExerciseType, WorkoutSession, Stats
        │   └── SessionStore.swift    Persistence + logique
        ├── Managers/
        │   └── GarminManager.swift   Communication Bluetooth
        └── Views/
            ├── ContentView.swift     Navigation tabs
            ├── HomeView.swift        Accueil + stats rapides
            ├── WorkoutConfigView.swift  Config + envoi à la montre
            ├── HistoryView.swift     Historique filtrable
            ├── SessionDetailView.swift  Détail séance (tir par tir)
            └── StatsView.swift       Stats globales + graphique
```

---

## Boutons de la montre (résumé)

| Bouton | Pendant l'exercice | Menu |
|--------|-------------------|------|
| ↑ Haut | ✅ Tir réussi | Scroll haut |
| ↓ Bas  | ❌ Tir raté   | Scroll bas  |
| ▶ Start | — | Valider |
| ← Back | Annuler séance | Retour |

---

## Dépannage

**"Cannot find symbol"** → Vérifie que tous les `.mc` sont bien dans `source/`

**"Device not found"** → Lance le simulateur Garmin Connect IQ

**L'app ne reçoit pas les données** → Vérifie que Garmin Connect tourne en arrière-plan sur iPhone

**Build iOS échoue avec Charts** → Charts est intégré dans Swift 5.5+ (iOS 16+). Si tu cibles iOS 15, remplace `import Charts` par Swift Charts disponible via SPM.
