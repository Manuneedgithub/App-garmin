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

    function initialize() {
        _retryCount = 0;
        _timer      = null;
        sendNext();
    }

    // Envoie la prochaine séance de la queue
    function sendNext() as Void {
        cancelTimer();
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
            cancelTimer();
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
