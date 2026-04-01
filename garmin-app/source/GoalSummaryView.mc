import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// RÉSUMÉ FINAL — Mode Objectif
//
//   ┌──────────────────────────┐
//   │      Résultat            │  gris xtiny
//   │    Lancer Franc          │  blanc tiny
//   │                          │
//   │       10 / 23            │  blanc grand : mis/total
//   │        43%               │  coloré selon perf
//   │                          │
//   │  Objectif : 10 ✓         │  vert tiny
//   │                          │
//   │  ▶ Sauvegarder           │  gris xtiny
//   │  ↩ Quitter               │  gris xtiny
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalSummaryView extends WatchUi.View {
    private var _session as GoalSession;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session as GoalSession) {
        View.initialize();
        _session = session;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w   = dc.getWidth();
        var cx  = w / 2;
        var pct = _session.percentage();

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Titre
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 28, Graphics.FONT_XTINY, "R\u00e9sultat",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Nom exercice
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score mis / total
        var scoreText = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 98, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pourcentage
        var pctColor = scoreColor(pct);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 140, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif atteint
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 168, Graphics.FONT_XTINY,
                    "Objectif : " + _session.targetMade.toString() + " \u2713",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 200, Graphics.FONT_XTINY, "\u25b6 Sauvegarder",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 220, Graphics.FONT_XTINY, "\u21a9 Quitter",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function scoreColor(pct as Number) as Number {
        if (pct >= 70) { return COLOR_GREEN; }
        if (pct >= 50) { return COLOR_ORANGE; }
        return COLOR_RED;
    }
}

class GoalSummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _session as GoalSession;

    function initialize(session as GoalSession) {
        BehaviorDelegate.initialize();
        _session = session;
    }

    // SELECT → envoyer à l'iPhone + retour menu
    function onSelect() as Boolean {
        Communications.transmit(_session.toDictionary(), null, new GoalTransmitListener());
        // Retour au menu principal (3 pops : GoalSummary, GoalView, GoalMenu)
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // BACK → quitter sans envoyer
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

class GoalTransmitListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }
    function onComplete() as Void {
    }
    function onError() as Void {
    }
}
