# Design Spec — Connexion directe Garmin → iPhone via Connect IQ SDK

**Date :** 2026-03-31
**Scope :** Communication montre → iPhone
**Objectif :** Remplacer `Communications.openWebPage()` (URL avec popup) par `Communications.transmit()` (Bluetooth direct, silencieux)

---

## 1. Contexte et problème actuel

### Mécanisme actuel

```
Montre → openWebPage("baskettrainer://s?e=0&t=10&m=7&...")
       → Garmin Connect (affiche notification / popup)
       → iOS onOpenURL → GarminManager.handleIncomingURL()
```

**Problèmes :**
- L'utilisateur doit taper sur une notification ou confirmation Garmin Connect
- Les données sont encodées en query string (fragile, taille limitée)
- L'app iOS doit être ouverte manuellement

### Mécanisme cible

```
Montre → Communications.transmit(session.toDictionary())
       → Garmin Connect (transparent, en arrière-plan)
       → ConnectIQ SDK → GarminManager.didReceiveMessage()
```

**Résultat :** dès que l'utilisateur appuie sur "Sauvegarder" sur la montre, la séance apparaît dans l'app iPhone sans aucune action supplémentaire.

---

## 2. UUID de l'application

L'UUID doit être identique dans `manifest.xml` (Garmin) et dans `GarminManager.swift` (iOS) :

```
a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a
```

---

## 3. Changements côté montre (Monkey C)

### 3.1 `SummaryView.mc` — `sendToPhone()`

Remplacer :
```monkeyc
Communications.openWebPage(_session.toURL(), null, null);
```

Par :
```monkeyc
Communications.transmit(_session.toDictionary(), null, new TransmitListener());
```

Ajouter la classe `TransmitListener` dans `SummaryView.mc` :
```monkeyc
class TransmitListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }
    function onComplete() as Void {
        // Envoi réussi — rien à faire
    }
    function onError() as Void {
        // Échec silencieux — l'utilisateur peut réessayer via le menu
    }
}
```

### 3.2 `WorkoutSession.mc` — Supprimer `toURL()`

La méthode `toURL()` n'est plus utilisée. La supprimer entièrement.

`toDictionary()` reste inchangée — elle produit déjà le bon format :
```monkeyc
{
    "exerciseId"   => exerciseId,    // Number
    "exerciseName" => exerciseName,  // String
    "totalShots"   => totalShots,    // Number
    "madeShots"    => madeShots,     // Number
    "percentage"   => percentage(),  // Number
    "startTime"    => startTime,     // Number (timestamp Unix)
    "results"      => results,       // Array<Boolean>
    "duration"     => Time.now().value() - startTime  // Number (secondes)
}
```

---

## 4. Changements côté iPhone (Swift)

### 4.1 Xcode — Intégration du framework

1. Ouvrir `ios-app/BasketTrainer.xcodeproj` dans Xcode
2. Target → General → Frameworks, Libraries, and Embedded Content
3. Ajouter `ConnectIQ.xcframework` → choisir **Embed & Sign**

### 4.2 Info.plist — Clés requises

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

Le scheme `baskettrainer` est nécessaire pour que le SDK Connect IQ puisse réveiller l'app quand un message arrive.

### 4.3 `GarminManager.swift` — Réécriture complète

`GarminManager` devient un `IQDeviceEventDelegate` + `IQAppMessageDelegate`.

**Responsabilités :**
- Initialiser le SDK au démarrage
- Écouter les connexions/déconnexions de la montre
- S'enregistrer auprès du SDK pour recevoir les messages de l'app Garmin (via UUID)
- Parser le dictionnaire entrant → créer `WorkoutSession` → appeler `store.add()`

**Structure :**

```swift
import ConnectIQ

class GarminManager: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate {
    static let shared = GarminManager()

    private let appUUID = UUID(uuidString: "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a")!
    private let store = SessionStore.shared

    @Published var lastSyncDate: Date? = nil
    @Published var connectedDevice: IQDevice? = nil

    // Propriétés mode guidé (inchangées)
    @Published var guidedTemplate: ComplexTemplate? = nil
    @Published var guidedIndex: Int = 0
    @Published var guidedSeries: [ShotSeries] = []

    func setup() {
        ConnectIQ.sharedInstance().initialize(
            withUrlScheme: "baskettrainer",
            uiOverrideDelegate: nil
        )
        // Les devices sont enregistrés dans handleIncomingURL()
        // quand Garmin Connect réveille l'app avec la liste des appareils
    }

    // Appelé par BasketTrainerApp.onOpenURL
    // Garmin Connect ouvre l'app via "baskettrainer://devices?..." pour fournir les devices
    // ou via un payload SDK quand un message arrive
    func handleIncomingURL(_ url: URL) {
        guard let devices = ConnectIQ.sharedInstance().parseDeviceSelection(from: url),
              !devices.isEmpty else { return }

        ConnectIQ.sharedInstance().register(
            forDeviceEvents: devices as? [IQDevice] ?? [],
            delegate: self
        )
    }

    // IQDeviceEventDelegate — connexion/déconnexion d'un device
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        if status == .connected {
            connectedDevice = device
            let app = ConnectIQ.sharedInstance().getApp(
                withUUID: appUUID, forDevice: device
            )
            ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
        } else {
            connectedDevice = nil
        }
    }

    // IQAppMessageDelegate — réception du message depuis la montre
    func receivedMessage(_ message: Any, fromApp app: IQApp) {
        guard let dict = message as? [String: Any] else { return }
        parseAndStore(dict)
    }

    private func parseAndStore(_ dict: [String: Any]) {
        let exId      = dict["exerciseId"] as? Int ?? 0
        let total     = dict["totalShots"] as? Int ?? 0
        let made      = dict["madeShots"]  as? Int ?? 0
        let startTime = dict["startTime"]  as? Int ?? 0
        let duration  = dict["duration"]   as? Int ?? 0
        let rawResults = dict["results"] as? [Bool] ?? []

        var session = WorkoutSession(
            exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
            totalShots: total,
            madeShots: made,
            results: rawResults,
            date: Date(timeIntervalSince1970: TimeInterval(startTime))
        )
        session.duration = TimeInterval(duration)
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
                var complex = WorkoutSession.makeComplex(series: guidedSeries, date: session.date)
                complex.sentFromWatch = true
                store.add(complex)
                cancelGuidedSession()
            }
        } else {
            store.add(session)
        }
    }

    func startGuidedSession(_ template: ComplexTemplate) {
        guidedTemplate = template; guidedIndex = 0; guidedSeries = []
    }

    func cancelGuidedSession() {
        guidedTemplate = nil; guidedIndex = 0; guidedSeries = []
    }

    func addMockSession() {
        let results = (0..<10).map { _ in Bool.random() }
        store.add(WorkoutSession(
            exerciseType: ExerciseType.allCases.randomElement()!,
            totalShots: 10, madeShots: results.filter { $0 }.count, results: results
        ))
    }
}
```

### 4.4 `BasketTrainerApp.swift` — Inchangé

`onOpenURL` garde son rôle : transmettre l'URL au SDK pour le réveiller. La signature reste identique.

---

## 5. Flux de données complet

```
[Montre]
  Utilisateur appuie START → SummaryDelegate.onSelect()
  → Communications.transmit(session.toDictionary(), null, listener)

[Garmin Connect — transparent]
  Reçoit le paquet Bluetooth
  Si l'app iPhone est en fond → l'ouvre via scheme "baskettrainer"

[iPhone]
  BasketTrainerApp.onOpenURL("baskettrainer://...sdk-payload...")
  → garmin.handleIncomingURL(url)
  → ConnectIQ.sharedInstance().handleOpenURL(url)
  → GarminManager.receivedMessage(dict, fromApp:)
  → parseAndStore(dict)
  → store.add(session)
  → SessionStore publie → UI se met à jour
```

---

## 6. Gestion d'erreur

- **`TransmitListener.onError()`** (Garmin) : échec silencieux. La montre ne renouvelle pas automatiquement. L'utilisateur peut relancer depuis le menu si besoin — cas rare en pratique (Bluetooth déconnecté).
- **`receivedMessage` avec data malformée** (iOS) : guard sur le cast `[String: Any]`. Si le cast échoue, la séance est ignorée sans crash.
- **Montre non connectée** : `connectedDevice == nil` dans GarminManager. Le statut dans `WorkoutConfigView` reflète cet état via `garmin.connectedDevice`.

---

## 7. Fichiers impactés

| Fichier | Nature |
|---|---|
| `garmin-app/source/SummaryView.mc` | Remplacer `openWebPage` par `transmit` + ajouter `TransmitListener` |
| `garmin-app/source/WorkoutSession.mc` | Supprimer `toURL()` |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Réécriture complète |
| `ios-app/BasketTrainer/Info.plist` | Ajouter `LSApplicationQueriesSchemes` + `CFBundleURLTypes` |
| Xcode project (`.xcodeproj`) | Ajouter `ConnectIQ.xcframework` (manuel dans Xcode) |

`BasketTrainerApp.swift`, `SessionStore.swift`, les modèles et toutes les vues : **inchangés**.
