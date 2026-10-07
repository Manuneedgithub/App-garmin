import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.System;
import Toybox.Attention;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// EXERCICE PHYSIQUE SUR LA MONTRE — chrono (HAUT démarre/arrête) ou
// minuteur à durée fixe (HAUT démarre, puis HAUT/BAS comptent les
// répétitions, SELECT valide et relance). Horloge murale (Time.now).
// ─────────────────────────────────────────────────

const PHYS_IDLE          = 0;
const PHYS_RUNNING       = 1;
const PHYS_COUNTDOWN     = 2;
const PHYS_ENTERING_REPS = 3;
const PHYS_MAX_REPS      = 50;

function physicalVibe(durationMs as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(100, durationMs)]);
    }
}

// Shortens text with ".." so it fits maxWidth pixels on the round display.
function physicalFit(dc as Graphics.Dc, text as String, font as Graphics.FontType,
                      maxWidth as Number) as String {
    if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }
    var len = text.length();
    while (len > 0) {
        len--;
        var candidate = text.substring(0, len) + "..";
        if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) { return candidate; }
    }
    return "..";
}

// "m:ss" — whole seconds only (the phone shows a decimal, the watch keeps it simple).
function physicalClock(elapsed as Double) as String {
    var t = elapsed.toNumber();
    if (t < 0) { t = 0; }
    var m = t / 60;
    var s = t % 60;
    return m.toString() + ":" + s.format("%02d");
}

class PhysicalRun {
    var name         as String;
    var kind         as String;    // "chrono" or "duration"
    var fixedSeconds as Number;    // only meaningful when kind == "duration"
    var startTime    as Number;    // unix seconds, set once when the run starts
    var attempts     as Array;     // [{"seconds" => Double} or {"reps" => Number}]

    var phase          as Number;    // PHYS_*
    var attemptStart   as Number;    // unix seconds when the current chrono/countdown attempt began
    var attemptStartMs as Number;    // System.getTimer() ms when the current attempt began (precise delta)
    var repsInput      as Number;

    function initialize(def as Dictionary) {
        name         = def["name"] as String;
        kind         = def["kind"] as String;
        fixedSeconds = (def["seconds"] instanceof Number) ? def["seconds"] as Number : 0;
        startTime    = Time.now().value();
        attempts     = [];
        phase          = PHYS_IDLE;
        attemptStart   = 0;
        attemptStartMs = 0;
        repsInput      = 0;
    }

    function elapsedInAttempt() as Double {
        var e = System.getTimer() - attemptStartMs;
        return (e < 0) ? 0.0 : e.toDouble() / 1000.0;
    }

    // HAUT
    function onUp() as Void {
        if (phase == PHYS_IDLE) {
            attemptStart   = Time.now().value();
            attemptStartMs = System.getTimer();
            phase = kind.equals("duration") ? PHYS_COUNTDOWN : PHYS_RUNNING;
        } else if (phase == PHYS_RUNNING) {
            attempts.add({ "seconds" => elapsedInAttempt() });
            phase = PHYS_IDLE;
        } else if (phase == PHYS_ENTERING_REPS) {
            if (repsInput < PHYS_MAX_REPS) { repsInput++; }
        }
        // phase == PHYS_COUNTDOWN: no-op — no pause/skip, same rule as Dribble.
    }

    // BAS
    function onDown() as Void {
        if (phase == PHYS_ENTERING_REPS && repsInput > 0) {
            repsInput--;
        }
    }

    // SELECT — only meaningful while entering a rep count
    function onConfirm() as Void {
        if (phase != PHYS_ENTERING_REPS) { return; }
        attempts.add({ "reps" => repsInput });
        repsInput      = 0;
        attemptStart   = Time.now().value();
        attemptStartMs = System.getTimer();
        phase          = PHYS_COUNTDOWN;   // relance automatiquement le minuteur
    }

    // Appelé chaque seconde ; renvoie true si le compte à rebours vient de
    // se terminer (pour déclencher la vibration côté vue).
    function tick() as Boolean {
        if (phase == PHYS_COUNTDOWN && elapsedInAttempt() >= fixedSeconds) {
            phase = PHYS_ENTERING_REPS;
            return true;
        }
        return false;
    }

    // Secondes restantes, arrondies au-dessus (même principe que le téléphone).
    function secondsLeft() as Number {
        var remaining = fixedSeconds.toDouble() - elapsedInAttempt();
        if (remaining <= 0) { return 0; }
        var whole = remaining.toNumber();
        if (remaining > whole) { whole = whole + 1; }
        return whole;
    }

    function hasAttempts() as Boolean {
        return attempts.size() > 0;
    }

    function finishPendingAttempt() as Void {
        if (phase == PHYS_ENTERING_REPS) {
            attempts.add({ "reps" => repsInput });
            repsInput = 0;
            phase = PHYS_IDLE;
        }
    }

    function toDictionary() as Dictionary {
        return {
            "type"         => "physicalSession",
            "exerciseName" => name,
            "kind"         => kind,
            "startTime"    => startTime,
            "attempts"     => attempts
        };
    }
}

class PhysicalRunView extends WatchUi.View {
    private var _run   as PhysicalRun;
    private var _timer as Timer.Timer or Null;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_RED    = 0xFF3333;
    private const COLOR_GRAY   = 0x888888;

    function initialize(run as PhysicalRun) {
        View.initialize();
        _run = run;
    }

    function onShow() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        if (_run.tick()) {
            physicalVibe(400);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 24, Graphics.FONT_XTINY, physicalFit(dc, _run.name, Graphics.FONT_XTINY, 150),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 48, Graphics.FONT_XTINY, _run.attempts.size().toString() + " tentative(s)",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_run.phase == PHYS_IDLE) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_MEDIUM, "Prêt ?",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 160, Graphics.FONT_XTINY, "↑ Démarrer",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_RUNNING) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_NUMBER_MEDIUM, physicalClock(_run.elapsedInAttempt()),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 160, Graphics.FONT_XTINY, "↑ Arrêter",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_COUNTDOWN) {
            var left = _run.secondsLeft();
            dc.setColor(left <= 3 ? COLOR_RED : COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_NUMBER_MEDIUM, left.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_run.phase == PHYS_ENTERING_REPS) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 90, Graphics.FONT_XTINY, "Répétitions ?",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, 130, Graphics.FONT_NUMBER_MEDIUM, _run.repsInput.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 170, Graphics.FONT_XTINY, "↑/↓  ● Valider",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "↩ Terminer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class PhysicalRunDelegate extends WatchUi.BehaviorDelegate {
    private var _run as PhysicalRun;

    function initialize(run as PhysicalRun) {
        BehaviorDelegate.initialize();
        _run = run;
    }

    function onNextPage() as Boolean {
        _run.onUp();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _run.onDown();
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        _run.onConfirm();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        _run.finishPendingAttempt();
        if (_run.hasAttempts()) {
            var dict = _run.toDictionary();
            Communications.transmit(dict, null, new TransmitListener(dict));
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
