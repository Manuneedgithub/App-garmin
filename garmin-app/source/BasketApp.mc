import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BasketApp extends Application.AppBase {
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

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }

    function onMessage(message as Object) as Void {
        if (!(message instanceof Dictionary)) { return; }
        var dict = message as Dictionary;
        if (dict["type"] instanceof String && (dict["type"] as String).equals("slot")) {
            if (!(dict["index"] instanceof Number) || !(dict["series"] instanceof Array)) { return; }
            var index  = dict["index"] as Number;
            if (index < 0 || index > 4) { return; }
            var series = dict["series"] as Array;
            Application.Storage.setValue("slot_" + index.toString(), series);
        }
    }
}

function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
