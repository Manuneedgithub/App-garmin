import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// ÉCRAN TRANSITION — Affiché après chaque série
// en mode Multi-exercices
//
//   ┌──────────────────────────┐
//   │      Série 2             │  gris xtiny
//   │   Lancer Franc           │  blanc tiny
//   │                          │
//   │       7 / 10             │  blanc number_medium
//   │        70%               │  vert/orange
//   │  ─────────────────────   │
//   │  ▶ Série suivante        │  orange
//   │  ↩ Terminer              │  gris
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class SeriesDoneView extends WatchUi.View {
    private var _session     as WorkoutSession;
    private var _accumulator as SessionAccumulator;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session as WorkoutSession, accumulator as SessionAccumulator) {
        View.initialize();
        _session     = session;
        _accumulator = accumulator;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Série X terminée"
        var seriesLabel = "S\u00e9rie " + _accumulator.seriesCount().toString() + " termin\u00e9e";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 32, Graphics.FONT_XTINY, seriesLabel,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Nom exercice
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 56, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score "7 / 10"
        var score = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 100, Graphics.FONT_NUMBER_MEDIUM, score,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pourcentage coloré
        var pct      = _session.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 142, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Séparateur
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(40, 164, w - 40, 164);

        // Instructions
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 183, Graphics.FONT_XTINY, "\u25b6 S\u00e9rie suivante",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 207, Graphics.FONT_XTINY, "\u21a9 Terminer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class SeriesDoneDelegate extends WatchUi.BehaviorDelegate {
    private var _accumulator as SessionAccumulator;

    function initialize(accumulator as SessionAccumulator) {
        BehaviorDelegate.initialize();
        _accumulator = accumulator;
    }

    // SELECT → exercice suivant
    function onSelect() as Boolean {
        var menu = new ExerciseMenuView();
        var del  = new ExerciseMenuDelegate(_accumulator);
        WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    // BACK → résumé final multi
    function onBack() as Boolean {
        var summaryView = new MultiSummaryView(_accumulator);
        var summaryDel  = new MultiSummaryDelegate(_accumulator);
        WatchUi.pushView(summaryView, summaryDel, WatchUi.SLIDE_LEFT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RÉSUMÉ FINAL MULTI — Affiché après "Terminer"
//
//   ┌──────────────────────────┐
//   │   Séance terminée        │  gris
//   │   3 séries               │  gris
//   │       18 / 30            │  blanc grand
//   │        60%               │  couleur
//   │      3min 42s            │  gris
//   │  ▶ Envoyer               │  orange
//   │  ↩ Quitter               │  gris
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class MultiSummaryView extends WatchUi.View {
    private var _accumulator as SessionAccumulator;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(accumulator as SessionAccumulator) {
        View.initialize();
        _accumulator = accumulator;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Séance terminée"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 28, Graphics.FONT_XTINY, "S\u00e9ance termin\u00e9e",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "X séries"
        var seriesLabel = _accumulator.seriesCount().toString() + " s\u00e9ries";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 48, Graphics.FONT_XTINY, seriesLabel,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score total
        var scoreText = _accumulator.totalMade().toString() + " / " + _accumulator.totalShots().toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 96, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pourcentage global
        var pct      = _accumulator.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 138, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Durée totale
        var elapsed = _accumulator.elapsedSeconds();
        var mins    = elapsed / 60;
        var secs    = elapsed % 60;
        var durStr  = mins.format("%d") + "min " + secs.format("%02d") + "s";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 165, Graphics.FONT_XTINY, durStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Instructions
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 194, Graphics.FONT_XTINY, "\u25b6 Envoyer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 216, Graphics.FONT_XTINY, "\u21a9 Quitter",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class MultiSummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _accumulator as SessionAccumulator;

    function initialize(accumulator as SessionAccumulator) {
        BehaviorDelegate.initialize();
        _accumulator = accumulator;
    }

    // SELECT → envoyer à l'iPhone et retour menu principal
    function onSelect() as Boolean {
        Communications.transmit(_accumulator.toDictionary(), null, null);
        popToRoot();
        return true;
    }

    // BACK → quitter sans envoyer
    function onBack() as Boolean {
        popToRoot();
        return true;
    }

    // Dépile toute la pile de vues pour revenir au menu principal.
    // Formule : 4 × nbSéries + 1 pops depuis MultiSummaryView
    // (ExMenu + ShotMenu + WorkView + SeriesDone) × N + 1 pour MultiSummary
    private function popToRoot() as Void {
        var pops = 4 * _accumulator.seriesCount() + 1;
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
