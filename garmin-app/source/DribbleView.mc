import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.Attention;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// ROUTINE DRIBBLE SUR LA MONTRE — minuteur sur l'horloge murale
// (Time.now), vibrations aux changements d'étape et sur les 3
// dernières secondes. Envoie la séance au téléphone à la fin.
// ─────────────────────────────────────────────────

function dribbleVibe(durationMs as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(100, durationMs)]);
    }
}

// Shortens text with ".." so it fits maxWidth pixels on the round display.
function dribbleFit(dc as Graphics.Dc, text as String, font as Graphics.FontType,
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

class DribbleRun {
    var name      as String;
    var steps     as Array;    // [{"drill" => String ("" = rest), "seconds" => Number}]
    var startTime as Number;   // unix
    var lastT     as Number;   // last second already processed for alerts
    var total     as Number;
    var finished  as Boolean;

    function initialize(def as Dictionary) {
        name      = def["name"] as String;
        steps     = def["steps"] as Array;
        startTime = Time.now().value();
        lastT     = 0;
        total     = dribbleTotalSeconds(steps);
        finished  = false;
    }

    function elapsed() as Number {
        var e = Time.now().value() - startTime;
        return (e < 0) ? 0 : e;
    }

    function secondsAt(i as Number) as Number {
        return (steps[i] as Dictionary)["seconds"] as Number;
    }

    function drillAt(i as Number) as String {
        return (steps[i] as Dictionary)["drill"] as String;
    }

    // Index of the step running at second t; steps.size() once finished.
    function stepIndexAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t < end) { return i; }
        }
        return steps.size();
    }

    function secondsLeftAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t < end) { return end - t; }
        }
        return 0;
    }

    // Same rules as DribbleTimerEngine.alerts on the phone:
    // 2 = step change / finish (t == end of a step), 1 = last-3-seconds tick
    // (only for steps longer than 3 s), 0 = nothing.
    function alertAt(t as Number) as Number {
        var end = 0;
        for (var i = 0; i < steps.size(); i++) {
            end += secondsAt(i);
            if (t == end) { return 2; }
            if (secondsAt(i) > 3 && t >= end - 3 && t < end) { return 1; }
        }
        return 0;
    }

    // Vibrates once (strongest alert crossed since the last call), returns true once finished.
    function advance() as Boolean {
        var e = elapsed();
        var strongest = 0;
        for (var t = lastT + 1; t <= e && t <= total; t++) {
            var a = alertAt(t);
            if (a > strongest) { strongest = a; }
        }
        lastT = (e > total) ? total : e;
        if (strongest == 2) {
            dribbleVibe(400);
        } else if (strongest == 1) {
            dribbleVibe(120);
        }
        if (e >= total) { finished = true; }
        return finished;
    }

    // Seconds per drill (rests excluded), in order of first appearance.
    function drillTimes() as Array {
        var out = [];
        for (var i = 0; i < steps.size(); i++) {
            var drill = drillAt(i);
            if (drill.equals("")) { continue; }
            var found = false;
            for (var j = 0; j < out.size(); j++) {
                var d = out[j] as Dictionary;
                if ((d["drill"] as String).equals(drill)) {
                    d["seconds"] = (d["seconds"] as Number) + secondsAt(i);
                    found = true;
                    break;
                }
            }
            if (!found) {
                out.add({ "drill" => drill, "seconds" => secondsAt(i) });
            }
        }
        return out;
    }

    function toDictionary() as Dictionary {
        return {
            "type"         => "dribbleSession",
            "routineName"  => name,
            "startTime"    => startTime,
            "totalSeconds" => total,
            "drillTimes"   => drillTimes()
        };
    }
}

class DribbleRunView extends WatchUi.View {
    private var _run   as DribbleRun;
    private var _timer as Timer.Timer or Null;
    private var _sent  as Boolean;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_BLUE   = 0x3399FF;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;

    function initialize(run as DribbleRun) {
        View.initialize();
        _run   = run;
        _timer = null;
        _sent  = false;
    }

    function onShow() as Void {
        if (_timer == null && !_run.finished) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
    }

    function onHide() as Void {
        stopTimer();
    }

    function onTick() as Void {
        if (_run.advance()) {
            stopTimer();
            sendResult();
        }
        WatchUi.requestUpdate();
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    private function sendResult() as Void {
        if (_sent) { return; }
        _sent = true;
        var dict = _run.toDictionary();
        // TransmitListener (SummaryView.mc) queues the dict in PendingQueue if the send fails.
        Communications.transmit(dict, null, new TransmitListener(dict));
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (_run.finished) {
            dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 60, Graphics.FONT_SMALL, "Routine terminée",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 100, Graphics.FONT_TINY, dribbleFit(dc, _run.name, Graphics.FONT_TINY, 220),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, 140, Graphics.FONT_NUMBER_MEDIUM, dribbleClock(_run.total),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 208, Graphics.FONT_XTINY, "▶ Terminer",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var t   = _run.elapsed();
        var idx = _run.stepIndexAt(t);
        var n   = _run.steps.size();
        if (idx >= n) { idx = n - 1; }   // between the last second and the finishing tick

        var drill  = _run.drillAt(idx);
        var isRest = drill.equals("");
        var label  = isRest ? "Repos" : drill;

        // Header: routine name + step counter
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        var counter = "  " + (idx + 1).toString() + "/" + n.toString();
        var counterW = dc.getTextWidthInPixels(counter, Graphics.FONT_XTINY);
        var headerName = dribbleFit(dc, _run.name, Graphics.FONT_XTINY, 150 - counterW);
        dc.drawText(cx, 28, Graphics.FONT_XTINY, headerName + counter,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Current step
        dc.setColor(isRest ? COLOR_BLUE : COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 64, Graphics.FONT_SMALL, dribbleFit(dc, label, Graphics.FONT_SMALL, 200),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Seconds left in the step
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 122, Graphics.FONT_NUMBER_MEDIUM, dribbleClock(_run.secondsLeftAt(t)),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Next step
        var nextText = "Fin";
        if (idx + 1 < n) {
            var nd = _run.drillAt(idx + 1);
            nextText = nd.equals("") ? "Repos" : nd;
        }
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 188, Graphics.FONT_XTINY,
                    dribbleFit(dc, "Ensuite : " + nextText, Graphics.FONT_XTINY, 200),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "↩ Abandonner",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class DribbleRunDelegate extends WatchUi.BehaviorDelegate {
    private var _run as DribbleRun;

    function initialize(run as DribbleRun) {
        BehaviorDelegate.initialize();
        _run = run;
    }

    // Finished: SELECT closes the summary. (Mid-routine SELECT does nothing — no pause/skip.)
    function onSelect() as Boolean {
        if (_run.finished) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        return true;
    }

    // BACK abandons a running routine (nothing is sent) or closes the summary.
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
