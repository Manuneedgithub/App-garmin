import Toybox.WatchUi;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// MENU 1 — Choix du type d'exercice
// ─────────────────────────────────────────────────

// Identifiants des exercices (Symbol = constante légère en Monkey C)
enum ExerciseId {
    EX_FREETHROW       = 0,
    EX_THREE_CENTER    = 1,
    EX_THREE_RIGHT_45  = 2,
    EX_THREE_LEFT_45   = 3,
    EX_THREE_CORNER_R  = 4,
    EX_THREE_CORNER_L  = 5,
    EX_MID_CENTER      = 6,
    EX_MID_RIGHT       = 7,
    EX_MID_LEFT        = 8
}

// Retourne le nom lisible d'un exercice
function exerciseName(id as Number) as String {
    switch (id) {
        case EX_FREETHROW:      return "Lancer Franc";
        case EX_THREE_CENTER:   return "3pts Centre";
        case EX_THREE_RIGHT_45: return "3pts 45\u00b0 Dr.";
        case EX_THREE_LEFT_45:  return "3pts 45\u00b0 Ga.";
        case EX_THREE_CORNER_R: return "3pts Coin Dr.";
        case EX_THREE_CORNER_L: return "3pts Coin Ga.";
        case EX_MID_CENTER:     return "Mi-dist Centre";
        case EX_MID_RIGHT:      return "Mi-dist Droite";
        case EX_MID_LEFT:       return "Mi-dist Gauche";
        default:                return "Inconnu";
    }
}

// Menu WatchUi natif : liste scrollable avec les noms d'exercices
class ExerciseMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Exercice"});
        addItem(new WatchUi.MenuItem("Lancer Franc",    null, EX_FREETHROW,       {}));
        addItem(new WatchUi.MenuItem("3pts Centre",     null, EX_THREE_CENTER,    {}));
        addItem(new WatchUi.MenuItem("3pts 45\u00b0 Dr.", null, EX_THREE_RIGHT_45, {}));
        addItem(new WatchUi.MenuItem("3pts 45\u00b0 Ga.", null, EX_THREE_LEFT_45,  {}));
        addItem(new WatchUi.MenuItem("3pts Coin Dr.",   null, EX_THREE_CORNER_R, {}));
        addItem(new WatchUi.MenuItem("3pts Coin Ga.",   null, EX_THREE_CORNER_L, {}));
        addItem(new WatchUi.MenuItem("Mi-dist Centre",  null, EX_MID_CENTER,     {}));
        addItem(new WatchUi.MenuItem("Mi-dist Droite",  null, EX_MID_RIGHT,      {}));
        addItem(new WatchUi.MenuItem("Mi-dist Gauche",  null, EX_MID_LEFT,       {}));
    }
}

class ExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    // Quand l'utilisateur valide un exercice → affiche le menu du nb de tirs
    function onSelect(item as WatchUi.MenuItem) as Void {
        var exerciseId = item.getId() as Number;
        var nextMenu  = new ShotCountMenuView(exerciseId);
        var nextDel   = new ShotCountMenuDelegate(exerciseId);
        WatchUi.pushView(nextMenu, nextDel, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
