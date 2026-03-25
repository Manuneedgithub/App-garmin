import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// MENU 1 — Choix du type d'exercice
// ─────────────────────────────────────────────────

// Identifiants des exercices (constantes Number)
const EX_FREETHROW       = 0;
const EX_THREE_CENTER    = 1;
const EX_THREE_RIGHT_45  = 2;
const EX_THREE_LEFT_45   = 3;
const EX_THREE_CORNER_R  = 4;
const EX_THREE_CORNER_L  = 5;
const EX_MID_CENTER      = 6;
const EX_MID_RIGHT       = 7;
const EX_MID_LEFT        = 8;

// Retourne le nom lisible d'un exercice
function getExerciseName(id as Number) as String {
    if (id == EX_FREETHROW)      { return "Lancer Franc"; }
    if (id == EX_THREE_CENTER)   { return "3pts Centre"; }
    if (id == EX_THREE_RIGHT_45) { return "3pts 45 Dr."; }
    if (id == EX_THREE_LEFT_45)  { return "3pts 45 Ga."; }
    if (id == EX_THREE_CORNER_R) { return "3pts Coin Dr."; }
    if (id == EX_THREE_CORNER_L) { return "3pts Coin Ga."; }
    if (id == EX_MID_CENTER)     { return "Mi-dist Centre"; }
    if (id == EX_MID_RIGHT)      { return "Mi-dist Droite"; }
    if (id == EX_MID_LEFT)       { return "Mi-dist Gauche"; }
    return "Inconnu";
}

// Menu WatchUi natif : liste scrollable avec les noms d'exercices
class ExerciseMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Exercice"});
        addItem(new WatchUi.MenuItem("Lancer Franc",   null, EX_FREETHROW,      {}));
        addItem(new WatchUi.MenuItem("3pts Centre",    null, EX_THREE_CENTER,   {}));
        addItem(new WatchUi.MenuItem("3pts 45 Dr.",    null, EX_THREE_RIGHT_45, null));
        addItem(new WatchUi.MenuItem("3pts 45 Ga.",    null, EX_THREE_LEFT_45,  {}));
        addItem(new WatchUi.MenuItem("3pts Coin Dr.",  null, EX_THREE_CORNER_R, null));
        addItem(new WatchUi.MenuItem("3pts Coin Ga.",  null, EX_THREE_CORNER_L, null));
        addItem(new WatchUi.MenuItem("Mi-dist Centre", null, EX_MID_CENTER,     {}));
        addItem(new WatchUi.MenuItem("Mi-dist Droite", null, EX_MID_RIGHT,      {}));
        addItem(new WatchUi.MenuItem("Mi-dist Gauche", null, EX_MID_LEFT,       {}));
    }
}

class ExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var exerciseId = item.getId() as Number;
        var nextMenu   = new ShotCountMenuView(exerciseId);
        var nextDel    = new ShotCountMenuDelegate(exerciseId);
        WatchUi.pushView(nextMenu, nextDel, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
