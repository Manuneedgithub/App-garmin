import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

// Point d'entrée principal de l'application
class BasketApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Retente l'envoi des sessions en attente (phone absent lors de la séance)
        retrySendPending();
    }

    // Envoie la 1ère session en attente — appelé aussi après chaque onComplete()
    static function retrySendPending() as Void {
        var pending = Application.Storage.getValue("pending") as Array?;
        if (pending == null || pending.size() == 0) { return; }
        var data = pending[0] as Dictionary;
        Communications.transmit(data, null, new RetryDelegate());
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Premier écran affiché : le menu de sélection d'exercice
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu = new ExerciseMenuView();
        var delegate = new ExerciseMenuDelegate();
        return [menu, delegate];
    }
}

// Raccourci global pour accéder à l'app
function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}

// Sauvegarde une session dans le stockage local de la montre
function savePendingSession(data as Dictionary) as Void {
    var pending = Application.Storage.getValue("pending") as Array?;
    if (pending == null) { pending = [] as Array; }
    pending.add(data);
    Application.Storage.setValue("pending", pending);
}

// Supprime la 1ère session en attente (après envoi réussi)
function removeFirstPending() as Void {
    var pending = Application.Storage.getValue("pending") as Array?;
    if (pending == null || pending.size() == 0) { return; }
    var newPending = [] as Array;
    for (var i = 1; i < pending.size(); i++) {
        newPending.add(pending[i]);
    }
    Application.Storage.setValue("pending", newPending);
}

// Delegate pour le retry automatique au démarrage
class RetryDelegate extends Communications.ConnectionListener {
    function initialize() { Communications.ConnectionListener.initialize(); }

    function onComplete() as Void {
        removeFirstPending();
        BasketApp.retrySendPending(); // envoie la suivante si elle existe
    }

    function onError() as Void {
        // Laisse en storage, réessaiera au prochain lancement
    }
}
