import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BasketApp extends Application.AppBase {
    private var _sync           as SyncManager or Null;
    private var _pendingRoutine as Dictionary or Null;

    function initialize() {
        AppBase.initialize();
        _sync           = null;
        _pendingRoutine = null;
    }

    function onStart(state as Dictionary?) as Void {
        _sync = new SyncManager();
        _sync.initialize();
    }

    function onStop(state as Dictionary?) as Void {
        _sync = null;
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }

    // Called when iPhone sends a message via sdk.sendMessage()
    function onMessage(message as Object) as Void {
        if (!(message instanceof Dictionary)) { return; }
        var dict = message as Dictionary;
        if (dict["type"] instanceof String && (dict["type"] as String).equals("routine")) {
            _pendingRoutine = dict;
        }
    }

    function getPendingRoutine() as Dictionary or Null {
        return _pendingRoutine;
    }

    // Caller must invoke this after consuming the routine (peek + clear pattern)
    function clearPendingRoutine() as Void {
        _pendingRoutine = null;
    }
}

function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
