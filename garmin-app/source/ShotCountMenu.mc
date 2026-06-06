import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// MENU 2 — Choix du nombre de tirs
// ─────────────────────────────────────────────────

class ShotCountMenuView extends WatchUi.Menu2 {

    function initialize(exerciseId as Number) {
        // Titre = nom de l'exercice choisi
        Menu2.initialize({:title => getExerciseName(exerciseId)});

        // Options de nombre de tirs
        addItem(new WatchUi.MenuItem("5 tirs",  null,  5, null));
        addItem(new WatchUi.MenuItem("10 tirs", null, 10, null));
        addItem(new WatchUi.MenuItem("15 tirs", null, 15, null));
        addItem(new WatchUi.MenuItem("20 tirs", null, 20, null));
        addItem(new WatchUi.MenuItem("25 tirs", null, 25, null));
        addItem(new WatchUi.MenuItem("30 tirs", null, 30, null));
    }
}

class ShotCountMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId  as Number;
    private var _shotTypeId  as Number;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(exerciseId  as Number,
                        shotTypeId  as Number,
                        accumulator as SessionAccumulator or Null) {
        Menu2InputDelegate.initialize();
        _exerciseId  = exerciseId;
        _shotTypeId  = shotTypeId;
        _accumulator = accumulator;
    }

    // Quand l'utilisateur valide un nombre → lance l'entraînement
    function onSelect(item as WatchUi.MenuItem) as Void {
        var totalShots = item.getId() as Number;
        var session    = new WorkoutSession(_exerciseId, totalShots, _shotTypeId);
        var view       = new WorkoutView(session, _accumulator);
        var delegate   = new WorkoutDelegate(session, view, _accumulator, null);
        WatchUi.pushView(view, delegate, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
