import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

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
const EX_FLOATER         = 9;
const EX_FORM_SHOT_S2S   = 10;
const EX_LAYUP_RIGHT     = 21;
const EX_LAYUP_LEFT      = 22;
const EX_EUROSTEP_RIGHT  = 23;
const EX_EUROSTEP_LEFT   = 24;
const EX_REVERSE_RIGHT   = 25;
const EX_REVERSE_LEFT    = 26;

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
    if (id == EX_FLOATER)        { return "Flotteur"; }
    if (id == EX_FORM_SHOT_S2S)  { return "Form S2S"; }
    if (id == EX_LAYUP_RIGHT)    { return "Layup Dr."; }
    if (id == EX_LAYUP_LEFT)     { return "Layup Ga."; }
    if (id == EX_EUROSTEP_RIGHT) { return "Eurostep Dr."; }
    if (id == EX_EUROSTEP_LEFT)  { return "Eurostep Ga."; }
    if (id == EX_REVERSE_RIGHT)  { return "Reverse Dr."; }
    if (id == EX_REVERSE_LEFT)   { return "Reverse Ga."; }
    if (id >= 11 && id <= 20) {
        var def = Application.Storage.getValue("customSpot_" + id.toString());
        if (def instanceof Dictionary && def["name"] instanceof String) {
            return def["name"] as String;
        }
        return "Inconnu";
    }
    return "Inconnu";
}

// Certains exercices n'ont qu'un seul type de tir logique — pas de menu à
// proposer, la valeur est forcée (0=Catch & Shoot, 1=Avec dribble,
// 2=A l'arret, cf. ShotTypeMenu.mc). Retourne null si le choix est libre.
function forcedShotTypeId(exerciseId as Number) as Number or Null {
    if (exerciseId == EX_FREETHROW) { return 2; }
    if (exerciseId == EX_LAYUP_RIGHT || exerciseId == EX_LAYUP_LEFT ||
        exerciseId == EX_EUROSTEP_RIGHT || exerciseId == EX_EUROSTEP_LEFT ||
        exerciseId == EX_REVERSE_RIGHT || exerciseId == EX_REVERSE_LEFT) {
        return 1;
    }
    return null;
}

// Menu WatchUi natif : liste scrollable avec les noms d'exercices
class ExerciseMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Exercice"});
        addItem(new WatchUi.MenuItem("Lancer Franc",   null, EX_FREETHROW,      null));
        addItem(new WatchUi.MenuItem("3pts Centre",    null, EX_THREE_CENTER,   null));
        addItem(new WatchUi.MenuItem("3pts 45 Dr.",    null, EX_THREE_RIGHT_45, null));
        addItem(new WatchUi.MenuItem("3pts 45 Ga.",    null, EX_THREE_LEFT_45,  null));
        addItem(new WatchUi.MenuItem("3pts Coin Dr.",  null, EX_THREE_CORNER_R, null));
        addItem(new WatchUi.MenuItem("3pts Coin Ga.",  null, EX_THREE_CORNER_L, null));
        addItem(new WatchUi.MenuItem("Mi-dist Centre", null, EX_MID_CENTER,     null));
        addItem(new WatchUi.MenuItem("Mi-dist Droite", null, EX_MID_RIGHT,      null));
        addItem(new WatchUi.MenuItem("Mi-dist Gauche", null, EX_MID_LEFT,       null));
        addItem(new WatchUi.MenuItem("Flotteur",       null, EX_FLOATER,        null));
        addItem(new WatchUi.MenuItem("Form S2S",       null, EX_FORM_SHOT_S2S,  null));
        addItem(new WatchUi.MenuItem("Layup Dr.",      null, EX_LAYUP_RIGHT,    null));
        addItem(new WatchUi.MenuItem("Layup Ga.",      null, EX_LAYUP_LEFT,     null));
        addItem(new WatchUi.MenuItem("Eurostep Dr.",   null, EX_EUROSTEP_RIGHT, null));
        addItem(new WatchUi.MenuItem("Eurostep Ga.",   null, EX_EUROSTEP_LEFT,  null));
        addItem(new WatchUi.MenuItem("Reverse Dr.",    null, EX_REVERSE_RIGHT,  null));
        addItem(new WatchUi.MenuItem("Reverse Ga.",    null, EX_REVERSE_LEFT,   null));

        // Spots personnalisés configurés depuis l'iPhone (emplacements 11-20) —
        // seuls ceux ayant une définition stockée apparaissent, comme SlotMenuView.
        for (var id = 11; id <= 20; id++) {
            var def = Application.Storage.getValue("customSpot_" + id.toString());
            if (def instanceof Dictionary && def["name"] instanceof String && def["emoji"] instanceof String) {
                addItem(new WatchUi.MenuItem(def["name"] as String, def["emoji"] as String, id, null));
            }
        }
    }
}

// Accepte un accumulateur optionnel (null = mode simple, non-null = mode multi)
class ExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _accumulator as SessionAccumulator or Null;

    function initialize(accumulator as SessionAccumulator or Null) {
        Menu2InputDelegate.initialize();
        _accumulator = accumulator;
    }

    // Certains exercices ont un type de tir forcé (lancer franc, lay up) —
    // on saute le menu de type de tir dans ce cas.
    function onSelect(item as WatchUi.MenuItem) as Void {
        var exerciseId = item.getId() as Number;
        var forced     = forcedShotTypeId(exerciseId);
        if (forced != null) {
            var menu = new ShotCountMenuView(exerciseId);
            var del  = new ShotCountMenuDelegate(exerciseId, forced as Number, _accumulator);
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else {
            var shotMenu = new ShotTypeMenuView(exerciseId);
            var del      = new ShotTypeMenuDelegate(exerciseId, 0, _accumulator);
            WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Délégué pour le mode Objectif : après avoir choisi l'exercice,
// affiche GoalMenuView au lieu de ShotCountMenuView
class ExerciseMenuGoalDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    // Même règle que ExerciseMenuDelegate : type de tir forcé → on saute
    // directement le menu de type de tir.
    function onSelect(item as WatchUi.MenuItem) as Void {
        var exerciseId = item.getId() as Number;
        var forced     = forcedShotTypeId(exerciseId);
        if (forced != null) {
            var view = new GoalMenuView(exerciseId, 10);
            var del  = new GoalMenuDelegate(view, exerciseId, forced as Number);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        } else {
            var shotMenu = new ShotTypeMenuView(exerciseId);
            var del      = new ShotTypeMenuDelegate(exerciseId, 1, null);
            WatchUi.pushView(shotMenu, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
