import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// MENU 2 — Choix du nombre de tirs
// ─────────────────────────────────────────────────

class ShotCountMenuView extends WatchUi.Menu2 {
    private var _exerciseId as Number;

    function initialize(exerciseId as Number) {
        _exerciseId = exerciseId;
        // Titre = nom de l'exercice choisi
        Menu2.initialize({:title => exerciseName(exerciseId)});

        // Options de nombre de tirs
        addItem(new WatchUi.MenuItem("5 tirs",  null,  5, {}));
        addItem(new WatchUi.MenuItem("10 tirs", null, 10, {}));
        addItem(new WatchUi.MenuItem("15 tirs", null, 15, {}));
        addItem(new WatchUi.MenuItem("20 tirs", null, 20, {}));
        addItem(new WatchUi.MenuItem("25 tirs", null, 25, {}));
        addItem(new WatchUi.MenuItem("30 tirs", null, 30, {}));
    }
}

class ShotCountMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId as Number;

    function initialize(exerciseId as Number) {
        Menu2InputDelegate.initialize();
        _exerciseId = exerciseId;
    }

    // Quand l'utilisateur valide un nombre → lance l'entraînement
    function onSelect(item as WatchUi.MenuItem) as Void {
        var totalShots = item.getId() as Number;
        var session    = new WorkoutSession(_exerciseId, totalShots);
        var view       = new WorkoutView(session);
        var delegate   = new WorkoutDelegate(session, view);
        WatchUi.pushView(view, delegate, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
