# Offline Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre à la montre de stocker les séances quand l'iPhone est absent, et les synchroniser automatiquement dès que la connexion est rétablie.

**Architecture:** `PendingQueue` persiste les séances dans `Application.Properties`. `SyncManager` flush la queue au démarrage avec retry 30s. L'iPhone réveille l'app montre via `sdk.open()` dès qu'il détecte la connexion.

**Tech Stack:** Monkey C (Connect IQ SDK 9.1.0), Swift 5 / iOS 16+, `Toybox.Application`, `Toybox.Timer`, `Toybox.Communications`

---

## Fichiers créés / modifiés

### Garmin
| Fichier | Action |
|---------|--------|
| `garmin-app/source/PendingQueue.mc` | Créer — file d'attente persistante dans Application.Properties |
| `garmin-app/source/SyncManager.mc` | Créer — flush + retry timer |
| `garmin-app/source/BasketApp.mc` | Modifier — stocker _sync, onStart/onStop |
| `garmin-app/source/SummaryView.mc` | Modifier — TransmitListener enqueue en cas d'erreur |
| `garmin-app/source/GoalSummaryView.mc` | Modifier — GoalTransmitListener idem |

### iPhone
| Fichier | Action |
|---------|--------|
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Modifier — appeler sdk.open() à la connexion |

---

## Task 1 : PendingQueue.mc — File d'attente persistante

**Files:**
- Create: `garmin-app/source/PendingQueue.mc`

- [ ] **Step 1 : Créer `PendingQueue.mc`**

```monkeyc
import Toybox.Application;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// File d'attente persistante des séances à envoyer
// Stockée dans Application.Properties sous "pendingQ"
// Survit aux redémarrages de l'app montre.
// Max 20 séances pour protéger la mémoire embarquée.
// ─────────────────────────────────────────────────
class PendingQueue {
    static const MAX_SIZE = 20;
    static const KEY      = "pendingQ";

    // Lit le tableau depuis Properties (tableau vide si absent)
    private static function load() as Array {
        var raw = Application.Properties.getValue(KEY);
        if (raw == null) { return new [0]; }
        return raw as Array;
    }

    // Sauvegarde le tableau dans Properties
    private static function save(arr as Array) as Void {
        Application.Properties.setValue(KEY, arr);
    }

    // Ajoute une séance en attente (no-op si queue pleine)
    static function enqueue(dict as Dictionary) as Void {
        var arr = load();
        if (arr.size() >= MAX_SIZE) { return; }
        arr.add(dict);
        save(arr);
    }

    // Retire et retourne le premier élément (null si vide)
    static function dequeue() as Dictionary or Null {
        var arr = load();
        if (arr.size() == 0) { return null; }
        var item = arr[0] as Dictionary;
        arr.remove(arr[0]);
        save(arr);
        return item;
    }

    // Lit sans supprimer (null si vide)
    static function peek() as Dictionary or Null {
        var arr = load();
        if (arr.size() == 0) { return null; }
        return arr[0] as Dictionary;
    }

    // Nombre de séances en attente
    static function size() as Number {
        return load().size();
    }

    // True si aucune séance en attente
    static function isEmpty() as Boolean {
        return load().size() == 0;
    }
}
```

- [ ] **Step 2 : Commit**

```bash
git add garmin-app/source/PendingQueue.mc
git commit -m "feat(garmin): add PendingQueue for offline session storage"
```

---

## Task 2 : SyncManager.mc — Flush + retry

**Files:**
- Create: `garmin-app/source/SyncManager.mc`

- [ ] **Step 1 : Créer `SyncManager.mc`**

```monkeyc
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;

// ─────────────────────────────────────────────────
// Gère l'envoi différé des séances en attente.
// Instancié dans BasketApp.onStart().
// Algorithme :
//   1. Au démarrage : sendNext()
//   2. onComplete → dequeue, sendNext suivant
//   3. onError → retry après 30s, max 3 fois
//      puis abandon de la séance et passage à la suivante
// ─────────────────────────────────────────────────
class SyncManager {
    private var _retryCount as Number;
    private var _timer      as Timer.Timer or Null;

    static const MAX_RETRIES    = 3;
    static const RETRY_DELAY_MS = 30000;

    function initialize() as Void {
        _retryCount = 0;
        _timer      = null;
        sendNext();
    }

    // Envoie la prochaine séance de la queue
    function sendNext() as Void {
        if (PendingQueue.isEmpty()) { return; }
        var dict = PendingQueue.peek();
        if (dict == null) { return; }
        Communications.transmit(dict, null, new SyncTransmitListener(self));
    }

    // Appelé par SyncTransmitListener.onComplete()
    function onTransmitComplete() as Void {
        PendingQueue.dequeue();
        _retryCount = 0;
        cancelTimer();
        sendNext();
    }

    // Appelé par SyncTransmitListener.onError()
    function onTransmitError() as Void {
        _retryCount++;
        if (_retryCount < MAX_RETRIES) {
            _timer = new Timer.Timer();
            _timer.start(method(:sendNext), RETRY_DELAY_MS, false);
        } else {
            // Abandon de cette séance après MAX_RETRIES échecs
            PendingQueue.dequeue();
            _retryCount = 0;
            cancelTimer();
            sendNext();
        }
    }

    private function cancelTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }
}

// ─────────────────────────────────────────────────
// Listener dédié au SyncManager (distinct du
// TransmitListener des views)
// ─────────────────────────────────────────────────
class SyncTransmitListener extends Communications.ConnectionListener {
    private var _manager as SyncManager;

    function initialize(manager as SyncManager) {
        Communications.ConnectionListener.initialize();
        _manager = manager;
    }

    function onComplete() as Void {
        _manager.onTransmitComplete();
    }

    function onError() as Void {
        _manager.onTransmitError();
    }
}
```

- [ ] **Step 2 : Commit**

```bash
git add garmin-app/source/SyncManager.mc
git commit -m "feat(garmin): add SyncManager with retry logic for offline queue flush"
```

---

## Task 3 : BasketApp.mc — Stocker _sync

**Files:**
- Modify: `garmin-app/source/BasketApp.mc`

État actuel du fichier :
```monkeyc
class BasketApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }
}
```

- [ ] **Step 1 : Modifier `BasketApp.mc`**

Remplacer le contenu complet par :

```monkeyc
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Point d'entrée principal de l'application
class BasketApp extends Application.AppBase {
    // Stocké en instance pour éviter le garbage collection du SyncManager
    private var _sync as SyncManager or Null;

    function initialize() {
        AppBase.initialize();
        _sync = null;
    }

    function onStart(state as Dictionary?) as Void {
        _sync = new SyncManager();
        _sync.initialize();
    }

    function onStop(state as Dictionary?) as Void {
        _sync = null;
    }

    // Premier écran affiché : choix du mode d'entraînement
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }
}

// Raccourci global pour accéder à l'app
function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
```

- [ ] **Step 2 : Commit**

```bash
git add garmin-app/source/BasketApp.mc
git commit -m "feat(garmin): wire SyncManager into BasketApp lifecycle"
```

---

## Task 4 : SummaryView.mc — TransmitListener avec enqueue

**Files:**
- Modify: `garmin-app/source/SummaryView.mc`

Le `TransmitListener` actuel (lignes 150-162) ignore `onError()`. Il faut le remplacer par un listener qui stocke la séance en cas d'échec. Il faut aussi passer le dictionnaire au listener au moment de l'appel.

- [ ] **Step 1 : Modifier `TransmitListener` dans `SummaryView.mc`**

Remplacer le bloc `sendToPhone()` + `TransmitListener` (lignes 141-162) par :

```monkeyc
    // Envoie via transmit() → CIQ SDK → app iPhone
    // En cas d'échec, la séance est mise en queue pour envoi différé
    private function sendToPhone() as Void {
        var dict = _session.toDictionary();
        Communications.transmit(dict, null, new TransmitListener(dict));
    }
}

// ─────────────────────────────────────────────────
// LISTENER — Résultat de l'envoi Bluetooth
// En cas d'erreur, enqueue pour sync différée
// ─────────────────────────────────────────────────
class TransmitListener extends Communications.ConnectionListener {
    private var _dict as Dictionary;

    function initialize(dict as Dictionary) {
        Communications.ConnectionListener.initialize();
        _dict = dict;
    }

    function onComplete() as Void {
        // Envoi réussi — rien à faire
    }

    function onError() as Void {
        // Bluetooth déconnecté ou app iPhone absente → stocker pour envoi différé
        PendingQueue.enqueue(_dict);
    }
}
```

Note : la ligne `}` avant le commentaire ferme la classe `SummaryDelegate`.

- [ ] **Step 2 : Commit**

```bash
git add garmin-app/source/SummaryView.mc
git commit -m "feat(garmin): enqueue session on transmit failure in SummaryView"
```

---

## Task 5 : GoalSummaryView.mc — GoalTransmitListener avec enqueue

**Files:**
- Modify: `garmin-app/source/GoalSummaryView.mc`

Le `GoalTransmitListener` actuel (lignes 119-127) ignore `onError()`. Même modification que Task 4.

- [ ] **Step 1 : Modifier `GoalSummaryDelegate.onSelect()` et `GoalTransmitListener`**

Dans `GoalSummaryDelegate.onSelect()`, remplacer :
```monkeyc
Communications.transmit(_session.toDictionary(), null, new GoalTransmitListener());
```
par :
```monkeyc
var dict = _session.toDictionary();
Communications.transmit(dict, null, new GoalTransmitListener(dict));
```

Remplacer la classe `GoalTransmitListener` (lignes 119-127) par :

```monkeyc
class GoalTransmitListener extends Communications.ConnectionListener {
    private var _dict as Dictionary;

    function initialize(dict as Dictionary) {
        Communications.ConnectionListener.initialize();
        _dict = dict;
    }

    function onComplete() as Void {
    }

    function onError() as Void {
        PendingQueue.enqueue(_dict);
    }
}
```

- [ ] **Step 2 : Commit**

```bash
git add garmin-app/source/GoalSummaryView.mc
git commit -m "feat(garmin): enqueue session on transmit failure in GoalSummaryView"
```

---

## Task 6 : GarminManager.swift — Ouvrir l'app montre à la connexion

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

État actuel de `deviceStatusChanged` (lignes 68-76) :
```swift
func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
    if status == .connected {
        connectedDevice = device
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        sdk.register(forAppMessages: app, delegate: self)
    } else if connectedDevice?.uuid == device.uuid {
        connectedDevice = nil
    }
}
```

- [ ] **Step 1 : Ajouter `sdk.open()` dans `deviceStatusChanged`**

Remplacer `deviceStatusChanged` par :

```swift
func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
    if status == .connected {
        connectedDevice = device
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        sdk.register(forAppMessages: app, delegate: self)
        // Réveille l'app montre → BasketApp.onStart() → SyncManager.flush()
        sdk.open(app, openApplicationResult: nil)
    } else if connectedDevice?.uuid == device.uuid {
        connectedDevice = nil
    }
}
```

Note : si `sdk.open()` ne compile pas (nom de méthode à confirmer selon SDK 1.8.0), essayer `sdk.openApplication(app, openApplicationResult: nil)`. L'une des deux formulations est correcte.

- [ ] **Step 2 : Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git commit -m "feat(ios): open watch app on connect to trigger offline sync"
```

---

## Self-review checklist (pour l'implémenteur)

Après avoir terminé toutes les tâches, vérifier :

- [ ] `PendingQueue.isEmpty()` retourne `true` quand Properties ne contient rien (pas de crash sur `null`)
- [ ] `SyncManager.sendNext()` ne plante pas si la queue est vide
- [ ] `TransmitListener` et `GoalTransmitListener` reçoivent bien le dict en paramètre (pas de référence nulle)
- [ ] `BasketApp._sync` est non-null entre `onStart()` et `onStop()` (pas de garbage collection prématuré)
- [ ] `sdk.open()` compile — si non, essayer `sdk.openApplication()`
