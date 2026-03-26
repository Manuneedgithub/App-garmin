import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;

// ─────────────────────────────────────────────────
// ÉCRAN PRINCIPAL — Tracking tir par tir
//
// Layout sur FR255 (260x260px, rond) :
//
//   ┌──────────────────────────┐
//   │   [Série 2 • 01:23]      │  y=22  gris xtiny  (timer + compteur série si multi)
//   │    [Nom exercice]        │  y=44  gris xtiny
//   │                          │
//   │       7 / 10             │  y=108 blanc grand
//   │        70%               │  y=148 orange moyen
//   │                          │
//   │  ● ● ● ● ● ● ● ○ ○ ●    │  y=178 points colorés
//   │                          │
//   │  ↑ Réussi    ↓ Raté      │  y=218 gris petit
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class WorkoutView extends WatchUi.View {
    private var _session     as WorkoutSession;
    private var _accumulator as SessionAccumulator or Null;

    // Palette
    private const COLOR_BG      = Graphics.COLOR_BLACK;
    private const COLOR_WHITE   = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE  = 0xFF6600;
    private const COLOR_GRAY    = 0x888888;
    private const COLOR_GREEN   = 0x33CC66;
    private const COLOR_RED     = 0xFF3333;
    private const DOT_RADIUS    = 6;
    private const DOT_SPACING   = 15;

    function initialize(session as WorkoutSession, accumulator as SessionAccumulator or Null) {
        View.initialize();
        _session     = session;
        _accumulator = accumulator;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // Pas de layout XML, on dessine tout manuellement
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();   // 260
        var cx = w / 2;

        // ── Fond noir ──
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // ── Ligne du haut : timer (+ compteur série si multi) ──
        var startRef = (_accumulator != null)
            ? (_accumulator as SessionAccumulator).globalStartTime
            : _session.startTime;
        var elapsed  = Time.now().value() - startRef;
        var mins     = elapsed / 60;
        var secs     = elapsed % 60;
        var timerStr = mins.format("%d") + ":" + secs.format("%02d");

        var headerStr = timerStr;
        if (_accumulator != null) {
            var acc       = _accumulator as SessionAccumulator;
            var seriesNum = acc.seriesCount() + 1;  // +1 car la série en cours n'est pas encore ajoutée
            headerStr = "S\u00e9rie " + seriesNum.toString() + " \u2022 " + timerStr;
        }
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_XTINY, headerStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Nom de l'exercice (petit, gris) ──
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 44, Graphics.FONT_XTINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Compteur principal  "7 / 10" (grand, blanc) ──
        var shotText = _session.currentShot.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 108, Graphics.FONT_NUMBER_MEDIUM, shotText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Pourcentage (moyen, orange) ──
        var pctText = _session.percentage().toString() + "%";
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 148, Graphics.FONT_MEDIUM, pctText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Points de résultats ──
        drawResultDots(dc, cx, 180);

        // ── Instructions boutons ──
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 48, 220, Graphics.FONT_XTINY, "\u2191 R\u00e9ussi",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 48, 220, Graphics.FONT_XTINY, "\u2193 R\u00e9t\u00e9",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Dessine les petits points colorés montrant l'historique des tirs
    private function drawResultDots(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var count = _session.results.size();
        if (count == 0) { return; }

        // On affiche au maximum les 12 derniers tirs
        var displayCount = count > 12 ? 12 : count;
        var startIdx     = count - displayCount;

        // Centrage horizontal
        var totalWidth = displayCount * DOT_SPACING;
        var startX     = cx - (totalWidth / 2) + (DOT_SPACING / 2);

        for (var i = 0; i < displayCount; i++) {
            var made  = _session.results[startIdx + i] as Boolean;
            var color = made ? COLOR_GREEN : COLOR_RED;
            var x     = startX + (i * DOT_SPACING);

            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, cy, DOT_RADIUS);

            // Petit contour noir pour la lisibilité
            dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, cy, DOT_RADIUS);
        }
    }
}

// ─────────────────────────────────────────────────
// DELEGATE — Gestion des boutons pendant l'exercice
// ─────────────────────────────────────────────────
class WorkoutDelegate extends WatchUi.BehaviorDelegate {
    private var _session     as WorkoutSession;
    private var _accumulator as SessionAccumulator or Null;

    function initialize(session as WorkoutSession, view as WorkoutView, accumulator as SessionAccumulator or Null) {
        BehaviorDelegate.initialize();
        _session     = session;
        _accumulator = accumulator;
    }

    // Bouton HAUT → Tir réussi ✅
    function onNextPage() as Boolean {
        recordAndAdvance(true);
        return true;
    }

    // Bouton BAS → Tir raté ❌
    function onPreviousPage() as Boolean {
        recordAndAdvance(false);
        return true;
    }

    // Bouton BACK → annuler et revenir
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function recordAndAdvance(made as Boolean) as Void {
        _session.recordShot(made);

        if (_session.isFinished()) {
            if (_accumulator != null) {
                // Mode multi : ajouter la série et afficher l'écran de transition
                var acc = _accumulator as SessionAccumulator;
                acc.addSeries(_session);
                var doneView = new SeriesDoneView(_session, acc);
                var doneDel  = new SeriesDoneDelegate(acc);
                WatchUi.pushView(doneView, doneDel, WatchUi.SLIDE_LEFT);
            } else {
                // Mode simple : écran de résumé standard
                var summaryView = new SummaryView(_session);
                var summaryDel  = new SummaryDelegate(_session);
                WatchUi.pushView(summaryView, summaryDel, WatchUi.SLIDE_LEFT);
            }
        } else {
            WatchUi.requestUpdate();
        }
    }
}
