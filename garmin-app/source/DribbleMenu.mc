import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

// ─────────────────────────────────────────────────
// MENU DRIBBLE — 5 emplacements de routines reçues du téléphone
// ─────────────────────────────────────────────────

// m:ss
function dribbleClock(totalSeconds as Number) as String {
    var m = totalSeconds / 60;
    var s = totalSeconds % 60;
    return m.toString() + ":" + s.format("%02d");
}

function dribbleTotalSeconds(steps as Array) as Number {
    var t = 0;
    for (var i = 0; i < steps.size(); i++) {
        t += (steps[i] as Dictionary)["seconds"] as Number;
    }
    return t;
}

class DribbleSlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Dribble"});
        for (var i = 0; i < 5; i++) {
            var def   = Application.Storage.getValue("dribbleSlot_" + i.toString());
            var label = "Routine " + (i + 1).toString();
            var sub   = "vide";
            if (def instanceof Dictionary && def["name"] instanceof String && def["steps"] instanceof Array) {
                label = def["name"] as String;
                sub   = dribbleClock(dribbleTotalSeconds(def["steps"] as Array));
            }
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class DribbleSlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId() as Number;
        var def   = Application.Storage.getValue("dribbleSlot_" + index.toString());
        if (!(def instanceof Dictionary) || !(def["steps"] instanceof Array)) { return; }
        var run  = new DribbleRun(def as Dictionary);
        var view = new DribbleRunView(run);
        var del  = new DribbleRunDelegate(run);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
