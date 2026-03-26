import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// PREMIER ÉCRAN — Choix du mode de séance
//   • Séance Simple   → un seul exercice
//   • Multi-exercices → enchaîner plusieurs séries
// ─────────────────────────────────────────────────

class ModeMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "BasketTrainer"});
        addItem(new WatchUi.MenuItem("S\u00e9ance Simple",  null, 0, null));
        addItem(new WatchUi.MenuItem("Multi-exercices", null, 1, null));
    }
}

class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mode = item.getId() as Number;
        var accumulator = null;
        if (mode == 1) {
            // Mode multi : crée l'accumulateur qui vivra toute la séance
            accumulator = new SessionAccumulator();
        }
        var menu = new ExerciseMenuView();
        var del  = new ExerciseMenuDelegate(accumulator);
        WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
