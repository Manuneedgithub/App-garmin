import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// ÉCRAN TRACKING — Mode Objectif
//
//   ┌──────────────────────────┐
//   │      Lancer Franc        │  y=30  gris xtiny
//   │   Objectif : 10          │  y=55  blanc xtiny
//   │                          │
//   │       5 / 8              │  y=110 blanc grand : mis/total
//   │                          │
//   │  ████████░░░░░░░░        │  y=155 barre progression objectif
//   │                          │
//   │  ● ● ● ● ● ● ● ○ ○      │  y=190 points résultats
//   │                          │
//   │  ▲ Réussi   ▼ Raté       │  y=225 gris xtiny
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalView extends WatchUi.View {
    private var _session as GoalSession;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;
    private const DOT_RADIUS   = 6;
    private const DOT_SPACING  = 15;

    function initialize(session as GoalSession) {
        View.initialize();
        _session = session;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Nom exercice
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_XTINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 55, Graphics.FONT_XTINY,
                    "Objectif : " + _session.targetMade.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Compteur principal : mis / total tirs
        var shotText = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 110, Graphics.FONT_NUMBER_MEDIUM, shotText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Barre de progression vers l'objectif
        drawProgressBar(dc, cx, 155);

        // Points résultats (12 derniers)
        drawResultDots(dc, cx, 190);

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 48, 225, Graphics.FONT_XTINY, "\u2191 R\u00e9ussi",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 48, 225, Graphics.FONT_XTINY, "\u2193 Rat\u00e9",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawProgressBar(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var barW   = 160;
        var barH   = 10;
        var x      = cx - barW / 2;
        var pct    = (_session.madeShots * 100) / _session.targetMade;
        if (pct > 100) { pct = 100; }
        var filled = (barW * pct) / 100;

        // Fond gris
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, cy, barW, barH, 5);

        // Remplissage : orange → vert quand objectif atteint
        if (filled > 0) {
            var barColor = (_session.madeShots >= _session.targetMade) ? COLOR_GREEN : COLOR_ORANGE;
            dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, cy, filled, barH, 5);
        }
    }

    private function drawResultDots(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var count = _session.results.size();
        if (count == 0) { return; }
        var displayCount = count > 12 ? 12 : count;
        var startIdx     = count - displayCount;
        var totalWidth   = displayCount * DOT_SPACING;
        var startX       = cx - (totalWidth / 2) + (DOT_SPACING / 2);

        for (var i = 0; i < displayCount; i++) {
            var made  = _session.results[startIdx + i] as Boolean;
            var color = made ? COLOR_GREEN : COLOR_RED;
            var x     = startX + (i * DOT_SPACING);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, cy, DOT_RADIUS);
            dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, cy, DOT_RADIUS);
        }
    }
}

// ─────────────────────────────────────────────────
// DELEGATE — Boutons pendant la session objectif
// ─────────────────────────────────────────────────
class GoalDelegate extends WatchUi.BehaviorDelegate {
    private var _session as GoalSession;

    function initialize(session as GoalSession, view as GoalView) {
        BehaviorDelegate.initialize();
        _session = session;
    }

    // Bouton HAUT → Tir réussi
    function onNextPage() as Boolean {
        _session.recordShot(true);
        if (_session.isGoalReached()) {
            showSummary();
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }

    // Bouton BAS → Tir raté
    function onPreviousPage() as Boolean {
        _session.recordShot(false);
        WatchUi.requestUpdate();
        return true;
    }

    // Bouton BACK → annuler
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function showSummary() as Void {
        var summaryView = new GoalSummaryView(_session);
        var summaryDel  = new GoalSummaryDelegate(_session);
        WatchUi.pushView(summaryView, summaryDel, WatchUi.SLIDE_LEFT);
    }
}
