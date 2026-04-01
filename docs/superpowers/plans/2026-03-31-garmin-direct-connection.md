# Connexion directe Garmin → iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer `Communications.openWebPage()` (URL avec popup utilisateur) par `Communications.transmit()` + ConnectIQ iOS SDK pour que les séances arrivent silencieusement sur l'iPhone dès la sauvegarde sur la montre.

**Architecture:** La montre encode la séance via `toDictionary()` déjà existant et l'envoie en Bluetooth via `transmit()`. L'iPhone intègre `ConnectIQ.xcframework` et reçoit le dictionnaire directement dans `GarminManager` via `IQAppMessageDelegate`. Le mécanisme URL (`openWebPage` / parsing query string) est entièrement supprimé.

**Tech Stack:** Monkey C / Connect IQ SDK 9.1.0 (montre), Swift / ConnectIQ.xcframework (iOS), Garmin Connect IQ iOS SDK — https://github.com/garmin/connectiq-companion-app-sdk-ios

---

## Fichiers impactés

| Fichier | Action |
|---|---|
| `garmin-app/source/SummaryView.mc` | Remplacer `openWebPage` par `transmit` + ajouter `TransmitListener` |
| `garmin-app/source/WorkoutSession.mc` | Supprimer `toURL()` |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Réécriture complète |
| `ios-app/BasketTrainer/Info.plist` | Supprimer `UIUserInterfaceStyle: Dark` (force dark mode OS — contredit le redesign adaptatif) |
| `ios-app/BasketTrainer.xcodeproj` | Ajouter `ConnectIQ.xcframework` (étape manuelle dans Xcode) |

**Non modifiés :** `BasketTrainerApp.swift`, `SessionStore.swift`, tous les modèles, toutes les vues.

---

## Contexte important

### Info.plist — déjà correct

Le fichier `ios-app/BasketTrainer/Info.plist` contient déjà :
- `CFBundleURLTypes` → scheme `baskettrainer` ✅
- `LSApplicationQueriesSchemes` → `com.garmin.connect.mobile` + `gcm-ciq` ✅
- `NSBluetoothAlwaysUsageDescription` ✅

Seule modification : supprimer `UIUserInterfaceStyle: Dark` (voir Task 1, Step 1).

### UUID de l'app

```
a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a
```

Doit être identique dans `manifest.xml` et dans `GarminManager.swift`.

### `toDictionary()` — déjà implémenté côté montre

```monkeyc
{
    "exerciseId"   => exerciseId,     // Number (0-8)
    "exerciseName" => exerciseName,   // String
    "totalShots"   => totalShots,     // Number
    "madeShots"    => madeShots,      // Number
    "percentage"   => percentage(),   // Number
    "startTime"    => startTime,      // Number (timestamp Unix)
    "results"      => results,        // Array<Boolean>
    "duration"     => Time.now().value() - startTime  // Number (secondes)
}
```

---

## Task 1 : Info.plist — Supprimer le dark mode forcé

**Files:**
- Modify: `ios-app/BasketTrainer/Info.plist`

- [ ] **Step 1 : Supprimer UIUserInterfaceStyle**

Dans `ios-app/BasketTrainer/Info.plist`, supprimer ces deux lignes :

```xml
<key>UIUserInterfaceStyle</key>
<string>Dark</string>
```

Le fichier résultant ne doit plus contenir ces clés. L'app utilisera désormais le réglage système iOS (suit le redesign adaptatif).

- [ ] **Step 2 : Build + vérifier**

`Cmd+B` dans Xcode. L'app doit compiler sans erreur. En simulateur, basculer Features → Toggle Appearance pour vérifier que light/dark mode fonctionne.

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Info.plist
git commit -m "fix: remove forced dark mode from Info.plist"
```

---

## Task 2 : Monkey C — Remplacer openWebPage par transmit

**Files:**
- Modify: `garmin-app/source/SummaryView.mc`
- Modify: `garmin-app/source/WorkoutSession.mc`

- [ ] **Step 1 : Ajouter TransmitListener dans SummaryView.mc**

À la fin de `garmin-app/source/SummaryView.mc`, après la classe `SummaryDelegate`, ajouter :

```monkeyc
// ─────────────────────────────────────────────────
// LISTENER — Résultat de l'envoi Bluetooth
// ─────────────────────────────────────────────────
class TransmitListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }

    function onComplete() as Void {
        // Envoi réussi — rien à faire
    }

    function onError() as Void {
        // Échec silencieux — Bluetooth déconnecté ou app iPhone absente
        // L'utilisateur peut sauvegarder à nouveau si besoin
    }
}
```

- [ ] **Step 2 : Remplacer sendToPhone() dans SummaryDelegate**

Dans `SummaryDelegate`, remplacer la méthode `sendToPhone()` :

```monkeyc
// Avant
private function sendToPhone() as Void {
    Communications.openWebPage(_session.toURL(), null, null);
}
```

Par :

```monkeyc
// Après
private function sendToPhone() as Void {
    Communications.transmit(_session.toDictionary(), null, new TransmitListener());
}
```

- [ ] **Step 3 : Supprimer toURL() dans WorkoutSession.mc**

Dans `garmin-app/source/WorkoutSession.mc`, supprimer entièrement la méthode `toURL()` (lignes 46-58) :

```monkeyc
// À SUPPRIMER — bloc entier :
// Encode la session en URL baskettrainer://s?... pour openWebPage()
function toURL() as String {
    var r = "";
    for (var i = 0; i < results.size(); i++) {
        r = r + ((results[i] as Boolean) ? "1" : "0");
    }
    var d = Time.now().value() - startTime;
    return "baskettrainer://s?e=" + exerciseId.toString()
         + "&t=" + totalShots.toString()
         + "&m=" + madeShots.toString()
         + "&st=" + startTime.toString()
         + "&r=" + r
         + "&d=" + d.toString();
}
```

La méthode `toDictionary()` reste intacte.

- [ ] **Step 4 : Build Garmin pour vérifier**

Dans VS Code : `Ctrl+Shift+P` → "Monkey C: Build for Device" (target : Forerunner 255).

Attendu : 0 erreurs. Si warning sur `Communications.transmit` — inoffensif (même pattern que `openWebPage` avant).

- [ ] **Step 5 : Commit**

```bash
git add garmin-app/source/SummaryView.mc garmin-app/source/WorkoutSession.mc
git commit -m "feat(garmin): replace openWebPage with direct transmit via Bluetooth"
```

---

## Task 3 : iOS — Intégrer ConnectIQ.xcframework dans Xcode

Cette tâche est **manuelle dans Xcode** — elle ne peut pas être automatisée par un script.

**Files:**
- Modify: `ios-app/BasketTrainer.xcodeproj` (via Xcode UI)

- [ ] **Step 1 : Télécharger le SDK**

Aller sur https://github.com/garmin/connectiq-companion-app-sdk-ios/releases

Télécharger la dernière release (fichier `.zip` ou `.xcframework` directement). Extraire `ConnectIQ.xcframework`.

- [ ] **Step 2 : Ajouter le framework dans Xcode**

1. Ouvrir `ios-app/BasketTrainer.xcodeproj` dans Xcode
2. Cliquer sur le projet dans le navigator → target `BasketTrainer`
3. Onglet **General** → section **Frameworks, Libraries, and Embedded Content**
4. Cliquer `+` → **Add Other…** → **Add Files…**
5. Sélectionner `ConnectIQ.xcframework`
6. Dans la colonne **Embed** : choisir **Embed & Sign**

- [ ] **Step 3 : Vérifier le bridging header (si nécessaire)**

`Cmd+B`. Si erreur `module 'ConnectIQ' not found` :

Le SDK est en Obj-C sans Swift module map. Créer un bridging header :

1. Xcode → File → New → File → **Objective-C File** → nommer `Dummy.m` → Xcode proposera de créer un bridging header → accepter
2. Supprimer `Dummy.m` (il servait juste à déclencher la création du header)
3. Dans le fichier `BasketTrainer-Bridging-Header.h` généré, ajouter :

```objc
#import <ConnectIQ/ConnectIQ.h>
```

4. Dans Build Settings du target, vérifier que **Objective-C Bridging Header** pointe vers `BasketTrainer/BasketTrainer-Bridging-Header.h`

- [ ] **Step 4 : Build pour confirmer**

`Cmd+B`. Attendu : 0 erreurs, pas de "module not found".

---

## Task 4 : iOS — Réécrire GarminManager.swift

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

- [ ] **Step 1 : Remplacer entièrement GarminManager.swift**

Remplacer tout le contenu de `ios-app/BasketTrainer/Managers/GarminManager.swift` par :

```swift
import Foundation
import Combine
import ConnectIQ

// ─────────────────────────────────────────────────
// GARMIN MANAGER — Réception via ConnectIQ SDK (Bluetooth direct)
// La montre envoie via Communications.transmit() → toDictionary()
// iOS reçoit via IQAppMessageDelegate.receivedMessage(_:fromApp:)
// ─────────────────────────────────────────────────

class GarminManager: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate {
    static let shared = GarminManager()

    // UUID identique à manifest.xml de l'app Garmin
    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!
    private let store = SessionStore.shared

    @Published var lastSyncDate: Date?    = nil
    @Published var connectedDevice: IQDevice? = nil

    // ── Mode guidé (templates complexes, inchangé) ──
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex:    Int = 0
    @Published var guidedSeries:   [ShotSeries] = []

    // ── Initialisation du SDK ──

    func setup() {
        ConnectIQ.sharedInstance().initialize(
            withUrlScheme: "baskettrainer",
            uiOverrideDelegate: nil
        )
        print("[GarminManager] ConnectIQ SDK initialisé")
    }

    // ── Appelé par BasketTrainerApp.onOpenURL ──
    // Garmin Connect ouvre l'app via "baskettrainer://..." quand la montre envoie des données.
    // handleOpenURL parse la liste des devices Garmin et retourne les IQDevice appairés.
    // On s'enregistre pour les events de chaque device.
    func handleIncomingURL(_ url: URL) {
        guard let devices = ConnectIQ.sharedInstance().handleOpenURL(
            url, sourceApplication: nil
        ), !devices.isEmpty else { return }

        for case let device as IQDevice in devices {
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
        }
    }

    // ── IQDeviceEventDelegate ──
    // Appelé quand le statut de connexion d'un device change.
    // Quand la montre se connecte → on s'enregistre pour recevoir les messages de notre app.
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        DispatchQueue.main.async {
            if status == .connected {
                self.connectedDevice = device
                let app = IQApp(uuid: self.appUUID, store: nil, device: device)
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
                print("[GarminManager] Montre connectée : \(device.friendlyName ?? "?")")
            } else {
                self.connectedDevice = nil
                print("[GarminManager] Montre déconnectée")
            }
        }
    }

    // ── IQAppMessageDelegate ──
    // Appelé quand la montre envoie un message via Communications.transmit().
    // `message` est le Dictionary produit par toDictionary() côté Monkey C.
    func receivedMessage(_ message: Any, fromApp app: IQApp) {
        guard let dict = message as? [String: Any] else {
            print("[GarminManager] Message reçu non parseable : \(type(of: message))")
            return
        }
        parseAndStore(dict)
    }

    // ── Parsing du dictionnaire → WorkoutSession ──

    private func parseAndStore(_ dict: [String: Any]) {
        let exId       = dict["exerciseId"] as? Int ?? 0
        let total      = dict["totalShots"] as? Int ?? 0
        let made       = dict["madeShots"]  as? Int ?? 0
        let startTime  = dict["startTime"]  as? Int ?? 0
        let duration   = dict["duration"]   as? Int ?? 0
        let rawResults = dict["results"]    as? [Bool] ?? []

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots:   total,
            madeShots:    made,
            results:      rawResults,
            date:         Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration      = TimeInterval(duration)
        session.sentFromWatch = true

        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.handleSessionOrGuided(session, results: rawResults, total: total, made: made)
        }
    }

    private func handleSessionOrGuided(
        _ session: WorkoutSession, results: [Bool], total: Int, made: Int
    ) {
        if let template = guidedTemplate {
            let ser = ShotSeries(
                exerciseType: session.exerciseType,
                totalShots: total, madeShots: made, results: results
            )
            guidedSeries.append(ser)
            guidedIndex += 1
            if guidedIndex >= template.series.count {
                var complex = WorkoutSession.makeComplex(
                    series: guidedSeries, date: session.date
                )
                complex.sentFromWatch = true
                store.add(complex)
                cancelGuidedSession()
            }
        } else {
            store.add(session)
        }
    }

    // ── Mode guidé ──

    func startGuidedSession(_ template: ComplexTemplate) {
        guidedTemplate = template; guidedIndex = 0; guidedSeries = []
    }

    func cancelGuidedSession() {
        guidedTemplate = nil; guidedIndex = 0; guidedSeries = []
    }

    // ── Debug / développement ──

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}
```

- [ ] **Step 2 : Build pour vérifier**

`Cmd+B` dans Xcode.

Si erreur `IQApp has no member 'init(uuid:store:device:)'` : consulter les headers du SDK et ajuster le constructeur. Selon la version du SDK, cela peut être :
```swift
// Variante A (plus courant)
let app = IQApp(uuid: appUUID, store: nil, device: device)
// Variante B
let app = IQApp(uuid: appUUID, storeUUID: nil, device: device)
```

Attendu : 0 erreurs après ajustement éventuel.

- [ ] **Step 3 : Tester avec addMockSession()**

Dans l'app (simulateur ou device), ouvrir HomeView et appeler `addMockSession()` via le bouton debug existant. Vérifier qu'une séance apparaît dans l'historique. Cela valide que `SessionStore`, `GarminManager` et les vues sont correctement connectés.

- [ ] **Step 4 : Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git commit -m "feat(ios): rewrite GarminManager with ConnectIQ SDK for direct Bluetooth reception"
```

---

## Task 5 : Test d'intégration avec la vraie montre

Cette tâche ne produit pas de code — elle valide l'intégration end-to-end.

**Prérequis :**
- App Garmin installée sur Forerunner 255 (via simulateur ou device)
- App iPhone installée sur un iPhone réel (le SDK ConnectIQ ne fonctionne pas sur simulateur iOS — Garmin Connect n'est pas disponible sur simulateur)
- Garmin Connect installé et connecté au compte Garmin sur le même iPhone

- [ ] **Step 1 : Lancer une séance sur la montre**

1. Lancer l'app BasketTrainer sur la Forerunner 255
2. Choisir un exercice et un nombre de tirs
3. Effectuer tous les tirs
4. Sur l'écran de résumé : appuyer sur **START** (bouton "Sauvegarder")

- [ ] **Step 2 : Vérifier la réception sur iPhone**

L'app iPhone doit recevoir la séance **sans aucun tap, notification ni popup**.

Vérifier dans HomeView → "Récentes" ou HistoryView que la nouvelle séance apparaît avec le badge ⌚.

- [ ] **Step 3 : Vérifier les logs Xcode**

En attachant Xcode au device iPhone (Product → Attach to Process), vérifier dans la console :

```
[GarminManager] ConnectIQ SDK initialisé
[GarminManager] Montre connectée : Forerunner 255
[GarminManager] (implicite — parseAndStore appelé)
```

- [ ] **Step 4 : Tester hors app ouverte**

Fermer l'app iPhone (mettre en arrière-plan).
Effectuer une nouvelle séance sur la montre et sauvegarder.
Ouvrir l'app iPhone → la séance doit être présente.

---

## Vérification finale

- [ ] L'app Garmin envoie via `transmit()` sans appel à `openWebPage`
- [ ] `toURL()` supprimé de `WorkoutSession.mc`
- [ ] `GarminManager` importe `ConnectIQ` et ne contient aucune référence à `URLComponents` ou `handleIncomingURL` pour parser des données
- [ ] `handleIncomingURL` dans `GarminManager` délègue au SDK (`handleOpenURL`) — il ne parse plus les query params
- [ ] `UIUserInterfaceStyle: Dark` absent de `Info.plist`
- [ ] Séances reçues avec `sentFromWatch = true` → badge ⌚ visible dans HistoryView
