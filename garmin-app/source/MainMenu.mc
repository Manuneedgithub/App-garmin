import Toybox.WatchUi;
import Toybox.Lang;

// Menu racine : choix du mode d'entraînement
class MainMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Basket Trainer"});
        addItem(new WatchUi.MenuItem("Tirs libres",       null, 0, null));
        addItem(new WatchUi.MenuItem("Objectif simple",   null, 1, null));
        addItem(new WatchUi.MenuItem("Entraînements",     null, 2, null));
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Number;
        if (id == 0) {
            // Tirs libres : mode existant
            var menu = new ExerciseMenuView();
            var del = new ExerciseMenuDelegate(null);
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else if (id == 1) {
            // Objectif simple : choisir exercice puis objectif
            var menu = new ExerciseMenuView();
            var del = new ExerciseMenuGoalDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else if (id == 2) {
            var menu = new SlotMenuView();
            var del  = new SlotMenuDelegate();
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
