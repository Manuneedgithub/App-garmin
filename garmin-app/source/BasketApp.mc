import Toybox.Application;
import Toybox.Communications;
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
        // The runtime only delivers incoming phone messages to a callback
        // registered here — it does not call any AppBase method on its own.
        Communications.registerForPhoneAppMessages(method(:onPhoneAppMessage));
    }

    function onStop(state as Dictionary?) as Void {
        _sync = null;
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu     = new MainMenuView();
        var delegate = new MainMenuDelegate();
        return [menu, delegate];
    }

    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        var message = msg.data;
        if (!(message instanceof Dictionary)) { return; }
        var dict = message as Dictionary;
        if (dict["type"] instanceof String && (dict["type"] as String).equals("slot")) {
            if (!(dict["index"] instanceof Number) || !(dict["series"] instanceof Array)) { return; }
            var index  = dict["index"] as Number;
            if (index < 0 || index > 4) { return; }
            var series = dict["series"] as Array;
            Application.Storage.setValue("slot_" + index.toString(), series);
        }
        if (dict["type"] instanceof String && (dict["type"] as String).equals("dribbleSlot")) {
            var dSlot = dict["index"];
            // Nested/Top-level integers from the phone can arrive as Long — accept both.
            if (!(dSlot instanceof Number || dSlot instanceof Long) || dSlot < 0 || dSlot > 4) { return; }
            if (!(dict["name"] instanceof String) || !(dict["steps"] instanceof Array)) { return; }
            var dRaw   = dict["steps"] as Array;
            var dClean = [];
            for (var d = 0; d < dRaw.size(); d++) {
                var dEntry = dRaw[d];
                if (!(dEntry instanceof Dictionary)) { continue; }
                var dSecs = dEntry["seconds"];
                if (!(dSecs instanceof Number || dSecs instanceof Long) || dSecs < 1) { continue; }
                var dDrill = dEntry["drill"];
                if (!(dDrill instanceof String)) { dDrill = ""; }
                dClean.add({ "drill" => dDrill, "seconds" => dSecs.toNumber() });
            }
            if (dClean.size() == 0) {
                Application.Storage.setValue("dribbleSlot_" + dSlot.toString(), null);
            } else {
                Application.Storage.setValue("dribbleSlot_" + dSlot.toString(),
                    { "name" => dict["name"], "steps" => dClean });
            }
        }
        if (dict["type"] instanceof String && (dict["type"] as String).equals("physicalSlot")) {
            var pSlot = dict["index"];
            if (!(pSlot instanceof Number || pSlot instanceof Long) || pSlot < 0 || pSlot > 4) { return; }
            if (!(dict["name"] instanceof String) || !(dict["kind"] instanceof String)) { return; }
            var pKind = dict["kind"] as String;
            if (!pKind.equals("chrono") && !pKind.equals("duration")) { return; }
            if (pKind.equals("duration")) {
                var pSeconds = dict["seconds"];
                if (!(pSeconds instanceof Number || pSeconds instanceof Long) || pSeconds < 5) { return; }
                Application.Storage.setValue("physicalSlot_" + pSlot.toString(),
                    { "name" => dict["name"], "kind" => pKind, "seconds" => pSeconds.toNumber() });
            } else {
                Application.Storage.setValue("physicalSlot_" + pSlot.toString(),
                    { "name" => dict["name"], "kind" => pKind, "seconds" => null });
            }
        }
        if (dict["type"] instanceof String && (dict["type"] as String).equals("customSpots")) {
            if (!(dict["spots"] instanceof Array)) { return; }
            var spots = dict["spots"] as Array;

            var seenIds = {};
            for (var i = 0; i < spots.size(); i++) {
                var entry = spots[i];
                if (!(entry instanceof Dictionary)) { continue; }
                var id = entry["id"];
                // Les entiers imbriqués dans un tableau de dictionnaires reçus depuis
                // le téléphone peuvent arriver typés Long plutôt que Number selon le
                // SDK — on accepte les deux pour ne pas rejeter silencieusement l'entrée.
                if (!(id instanceof Number || id instanceof Long) || id < 11 || id > 20) { continue; }
                if (!(entry["name"] instanceof String) || !(entry["emoji"] instanceof String)) { continue; }
                Application.Storage.setValue("customSpot_" + id.toString(),
                    { "name" => entry["name"], "emoji" => entry["emoji"] });
                seenIds[id] = true;
            }
            // Remplacement complet : tout emplacement réservé absent du
            // message est effacé — couvre les suppressions côté iPhone.
            for (var id = 11; id <= 20; id++) {
                if (!seenIds.hasKey(id)) {
                    Application.Storage.setValue("customSpot_" + id.toString(), null);
                }
            }
        }
    }
}

function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
