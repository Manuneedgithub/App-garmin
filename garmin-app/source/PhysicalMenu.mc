import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

// ─────────────────────────────────────────────────
// MENU PHYSIQUE — 5 emplacements d'exercices reçus du téléphone
// ─────────────────────────────────────────────────

class PhysicalSlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Physique"});
        for (var i = 0; i < 5; i++) {
            var def   = Application.Storage.getValue("physicalSlot_" + i.toString());
            var label = "Exercice " + (i + 1).toString();
            var sub   = "vide";
            if (def instanceof Dictionary && def["name"] instanceof String && def["kind"] instanceof String) {
                label = def["name"] as String;
                var kind = def["kind"] as String;
                if (kind.equals("duration") && def["seconds"] instanceof Number) {
                    sub = "Duree fixe " + (def["seconds"] as Number).toString() + "s";
                } else {
                    sub = "Chrono";
                }
            }
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class PhysicalSlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId() as Number;
        var def   = Application.Storage.getValue("physicalSlot_" + index.toString());
        if (!(def instanceof Dictionary) || !(def["kind"] instanceof String)) { return; }
        var run  = new PhysicalRun(def as Dictionary);
        var view = new PhysicalRunView(run);
        var del  = new PhysicalRunDelegate(run);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
