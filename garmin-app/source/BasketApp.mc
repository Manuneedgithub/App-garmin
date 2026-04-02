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
