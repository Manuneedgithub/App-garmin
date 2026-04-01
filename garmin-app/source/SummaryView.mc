import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// ÉCRAN DE RÉSUMÉ — Affiché à la fin de l'exercice
//
//   ┌──────────────────────────┐
//   │      Résultat            │  gris petit
//   │    Lancer Franc          │  blanc petit
//   │                          │
//   │        7 / 10            │  blanc grand
//   │         70%              │  orange ou vert selon score
//   │                          │
//   │  ★★★★☆☆☆☆☆☆             │  rating visuel
//   │                          │
//   │  [START] Sauvegarder     │  gris petit
//   │  [BACK]  Quitter         │  gris petit
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class SummaryView extends WatchUi.View {
    private var _session as WorkoutSession;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session as WorkoutSession) {
        View.initialize();
        _session = session;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        var pct = _session.percentage();

        // ── Fond ──
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // ── Titre "Résultat" ──
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 32, Graphics.FONT_XTINY, "R\u00e9sultat",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Nom de l'exercice ──
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 56, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Score "7 / 10" ──
        var scoreText = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 102, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Pourcentage (couleur selon performance) ──
        var pctColor = scoreColor(pct);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 142, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Barre de performance ──
        drawProgressBar(dc, cx, 168, pct);

        // ── Durée de la séance ──
        var elapsed = Time.now().value() - _session.startTime;
        var mins    = elapsed / 60;
        var secs    = elapsed % 60;
        var durStr  = mins.format("%d") + "min " + secs.format("%02d") + "s";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 188, Graphics.FONT_XTINY, durStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Instructions ──
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 208, Graphics.FONT_XTINY, "\u25b6 Sauvegarder",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 226, Graphics.FONT_XTINY, "\u21a9 Quitter",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function scoreColor(pct as Number) as Number {
        if (pct >= 70) { return COLOR_GREEN; }
        if (pct >= 50) { return COLOR_ORANGE; }
        return COLOR_RED;
    }

    private function drawProgressBar(dc as Graphics.Dc, cx as Number, cy as Number, pct as Number) as Void {
        var barW   = 140;
        var barH   = 8;
        var x      = cx - barW / 2;
        var filled = (barW * pct) / 100;

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, cy, barW, barH, 4);

        if (filled > 0) {
            dc.setColor(scoreColor(pct), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, cy, filled, barH, 4);
        }
    }
}

// ─────────────────────────────────────────────────
// DELEGATE — Actions sur l'écran de résumé
// ─────────────────────────────────────────────────
class SummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _session as WorkoutSession;

    function initialize(session as WorkoutSession) {
        BehaviorDelegate.initialize();
        _session = session;
    }

    function onSelect() as Boolean {
        sendToPhone();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // Envoie via transmit() → CIQ SDK → app iPhone (Bluetooth direct, sans tap utilisateur)
    private function sendToPhone() as Void {
        Communications.transmit(_session.toDictionary(), null, new TransmitListener());
    }
}

// ─────────────────────────────────────────────────
// LISTENER — Résultat de l'envoi Bluetooth
// ─────────────────────────────────────────────────
class TransmitListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }

    function onComplete() as Void {
        // Envoi réussi — rien à faire
    }

    function onError() as Void {
        // Échec silencieux — Bluetooth déconnecté ou app iPhone absente
    }
}
