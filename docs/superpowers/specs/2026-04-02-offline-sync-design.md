# Offline Sync — Basket Trainer

**Date :** 2026-04-02  
**Scope :** App Garmin (Monkey C) + GarminManager iPhone (Swift)

---

## Vue d'ensemble

Permettre à la montre d'enregistrer des séances même quand l'app iPhone n'est pas disponible, puis les synchroniser automatiquement dès que la connexion est rétablie.

**Flux :**
1. Séance terminée sur la montre → tentative `Communications.transmit()`
2. Si échec → séance stockée dans `PendingQueue` (`Application.Properties`)
3. Quand l'iPhone ouvre l'app → `openApplication()` réveille l'app montre
4. App montre démarre → `SyncManager` flush la queue (avec retry 30s, max 3 fois par séance)

---

## Garmin — Nouveaux fichiers

### `PendingQueue.mc`

File d'attente persistante dans `Application.Properties` (clé `"pendingQueue"`). Chaque entrée est un dictionnaire produit par `session.toDictionary()` — format identique aux envois directs, aucun changement côté iPhone.

```monkeyc
class PendingQueue {
    static const MAX_SIZE = 20;        // protection mémoire montre
    static const KEY      = "pendingQ";

    // Ajoute une séance en attente (no-op si queue pleine)
    static function enqueue(dict as Dictionary) as Void;

    // Retire et retourne le premier élément (null si vide)
    static function dequeue() as Dictionary or Null;

    // Lit sans supprimer (null si vide)
    static function peek() as Dictionary or Null;

    // Nombre de séances en attente
    static function size() as Number;

    // True si aucune séance en attente
    static function isEmpty() as Boolean;
}
```

Stockage interne : `Application.Properties.setValue(KEY, array)` où `array` est un `Array` de dictionnaires. À chaque `enqueue`/`dequeue`, on relit, modifie, et réécrit le tableau complet.

Limite à 20 séances : si la queue est pleine, `enqueue` ignore silencieusement la nouvelle séance (cas extrême — l'utilisateur n'a pas synchronisé depuis 20 séances).

---

### `SyncManager.mc`

Singleton global instancié dans `BasketApp.onStart()`. Gère le flush de la queue et le retry.

```monkeyc
class SyncManager {
    private var _retryCount as Number;   // tentatives sur la séance courante
    private var _timer      as Timer or Null;

    static const MAX_RETRIES    = 3;
    static const RETRY_DELAY_MS = 30000;  // 30 secondes

    // Appelé au démarrage : démarre le flush si queue non vide
    function initialize() as Void;

    // Envoie la prochaine séance de la queue
    // Appelé aussi par SyncTransmitListener.onComplete()
    function sendNext() as Void;

    // Appelé par SyncTransmitListener.onError()
    // Incrémente le compteur, schedule un retry ou passe à la suivante
    function onTransmitError() as Void;
}
```

**Algorithme `sendNext()` :**
1. Si `PendingQueue.isEmpty()` → stop
2. `peek()` la première séance
3. `Communications.transmit(dict, null, new SyncTransmitListener(self))`

**Algorithme `onTransmitError()` :**
1. `_retryCount++`
2. Si `_retryCount < MAX_RETRIES` → `Timer.schedule(sendNext, RETRY_DELAY_MS)`
3. Sinon → `dequeue()` (abandon de cette séance), `_retryCount = 0`, `sendNext()`

**`SyncTransmitListener` :**
- `onComplete()` → `PendingQueue.dequeue()`, `_retryCount = 0`, `syncManager.sendNext()`
- `onError()` → `syncManager.onTransmitError()`

---

## Garmin — Fichiers modifiés

### `BasketApp.mc`

Ajouter `_sync` comme variable d'instance de `BasketApp` pour éviter le garbage collection :

```monkeyc
class BasketApp extends Application.AppBase {
    private var _sync as SyncManager or Null;

    function onStart(state as Dictionary?) as Void {
        _sync = new SyncManager();
        _sync.initialize();
    }

    function onStop(state as Dictionary?) as Void {
        _sync = null;
    }
}
```

### `SummaryView.mc` — `TransmitListener`

Remplacer le `TransmitListener` existant (qui ignore `onError`) par un listener qui met en queue en cas d'échec :

```monkeyc
class TransmitListener extends Communications.ConnectionListener {
    private var _dict as Dictionary;

    function initialize(dict as Dictionary) {
        Communications.ConnectionListener.initialize();
        _dict = dict;
    }

    function onComplete() as Void { }

    function onError() as Void {
        PendingQueue.enqueue(_dict);
    }
}
```

L'appel dans `SummaryDelegate.sendToPhone()` devient :
```monkeyc
Communications.transmit(_session.toDictionary(), null,
    new TransmitListener(_session.toDictionary()));
```

### `GoalSummaryView.mc` — `GoalTransmitListener`

Même modification que `TransmitListener` ci-dessus : `onError()` appelle `PendingQueue.enqueue(_dict)`.

---

## iPhone — Fichier modifié

### `GarminManager.swift`

Dans `deviceStatusChanged(_:status:)`, quand `status == .connected`, après l'enregistrement des messages, appeler `openApplication()` pour réveiller l'app montre :

```swift
func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
    if status == .connected {
        connectedDevice = device
        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        sdk.register(forAppMessages: app, delegate: self)
        // Réveille l'app montre → déclenche SyncManager.flush()
        sdk.open(app, openApplicationResult: nil)
    } else if connectedDevice?.uuid == device.uuid {
        connectedDevice = nil
    }
}
```

---

## Ce qui ne change pas

- Format des messages envoyés à l'iPhone (`toDictionary()`) — identique, rétrocompatible
- `parseAndStore()` dans `GarminManager` — aucune modification nécessaire
- Modes Tirs libres et Objectif — comportement inchangé si l'iPhone est connecté
- `SessionAccumulator` — inchangé (les séances multi sont déjà sérialisées en dictionnaire)

---

## Limites connues

- **Queue pleine (>20 séances)** : les nouvelles séances sont ignorées silencieusement. Acceptable en usage normal (20 séances non synchronisées = cas extrême).
- **App montre fermée par l'utilisateur** : `openApplication()` depuis l'iPhone relance l'app, mais si l'utilisateur l'a fermée volontairement entre-temps il y a un délai de ~2s avant que `onStart()` s'exécute. C'est acceptable.
- **Pas de feedback visuel** : la montre n'affiche pas "X séances en attente" dans ce design. Ajout possible dans une future version.
- **`openApplication()` API** : cette méthode iOS du SDK Connect IQ s'appelle `open(_:openApplicationResult:)` — à confirmer à la compilation selon la version exacte du SDK 1.8.0.
