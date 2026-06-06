import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// MENU — Choix du type de tir
// ─────────────────────────────────────────────────

class ShotTypeMenuView extends WatchUi.Menu2 {
    function initialize(exerciseId as Number) {
        Menu2.initialize({:title => getExerciseName(exerciseId)});
        addItem(new WatchUi.MenuItem("Catch & Shoot", null, 0, null));
        addItem(new WatchUi.MenuItem("Avec dribble",  null, 1, null));
        addItem(new WatchUi.MenuItem("A l'arret",     null, 2, null));
    }
}

// _mode 0 = free/multi → ShotCountMenu
// _mode 1 = goal       → GoalMenu
class ShotTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _exerciseId  as Number;
    private var _mode        as Number;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(exerciseId  as Number,
                        mode        as Number,
                        accumulator as SessionAccumulator or Null) {
        Menu2InputDelegate.initialize();
        _exerciseId  = exerciseId;
        _mode        = mode;
        _accumulator = accumulator;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var shotTypeId = item.getId() as Number;
        if (_mode == 1) {
            var view = new GoalMenuView(_exerciseId, 10);
            var del  = new GoalMenuDelegate(view, _exerciseId, shotTypeId);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        } else {
            var menu = new ShotCountMenuView(_exerciseId);
            var del  = new ShotCountMenuDelegate(_exerciseId, shotTypeId, _accumulator);
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
