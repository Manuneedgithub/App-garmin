import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// RoutineRunner — drives a pre-defined series sequence
// ─────────────────────────────────────────────────

class RoutineRunner {
    private var _series as Array;   // [{exerciseId, totalShots}]
    private var _index  as Number;  // current position (0-based)
    var accumulator     as SessionAccumulator;

    function initialize(routine as Dictionary) {
        _series     = routine["series"] as Array;
        _index      = 0;
        accumulator = new SessionAccumulator();
    }

    function currentExerciseId() as Number {
        return (_series[_index] as Dictionary)["exerciseId"] as Number;
    }

    function currentTotalShots() as Number {
        return (_series[_index] as Dictionary)["totalShots"] as Number;
    }

    function exerciseIdAt(i as Number) as Number {
        return (_series[i] as Dictionary)["exerciseId"] as Number;
    }

    function totalShotsAt(i as Number) as Number {
        return (_series[i] as Dictionary)["totalShots"] as Number;
    }

    function seriesNumber() as Number { return _index + 1; }  // 1-based

    function totalSeries() as Number { return _series.size(); }

    function isComplete() as Boolean { return _index >= _series.size(); }

    function totalPlannedShots() as Number {
        var t = 0;
        for (var i = 0; i < _series.size(); i++) {
            t += (_series[i] as Dictionary)["totalShots"] as Number;
        }
        return t;
    }

    // Store result, transmit to iPhone, advance index
    function onSeriesComplete(session as WorkoutSession) as Void {
        accumulator.addSeries(session);
        var dict = session.toDictionary();
        Communications.transmit(dict, null, new TransmitListener(dict));
        _index++;
    }
}

// ─────────────────────────────────────────────────
// RoutineWaitView — shown when no routine is pending
// ─────────────────────────────────────────────────

class RoutineWaitView extends WatchUi.View {
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize() { View.initialize(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90,  Graphics.FONT_TINY,  "Aucune routine",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 118, Graphics.FONT_XTINY, "Ouvre l'app iPhone",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 136, Graphics.FONT_XTINY, "et appuie sur",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 154, Graphics.FONT_XTINY, "\"Guider la montre\"",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 215, Graphics.FONT_XTINY, "↩ Retour",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineWaitDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineStartView — routine overview before starting
// ─────────────────────────────────────────────────

class RoutineStartView extends WatchUi.View {
    private var _runner    as RoutineRunner;
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize(runner as RoutineRunner) {
        View.initialize();
        _runner = runner;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Routine guidée"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 24, Graphics.FONT_XTINY, "Routine guidée",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "N séries · X tirs"
        var header = _runner.totalSeries().toString() + " séries · "
                   + _runner.totalPlannedShots().toString() + " tirs";
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_TINY, header,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // List each series (up to 6)
        var n = _runner.totalSeries();
        for (var i = 0; i < n && i < 6; i++) {
            var line = (i + 1).toString() + ". "
                     + getExerciseName(_runner.exerciseIdAt(i))
                     + " ×" + _runner.totalShotsAt(i).toString();
            dc.setColor(i == 0 ? COLOR_ORANGE : COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 76 + i * 20, Graphics.FONT_XTINY, line,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instruction
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 224, Graphics.FONT_XTINY, "▶ START = commencer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineStartDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean {
        var sess = new WorkoutSession(_runner.currentExerciseId(), _runner.currentTotalShots());
        var view = new WorkoutView(sess, null);
        var del  = new WorkoutDelegate(sess, view, null, _runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineSeriesDoneView — inter-series bridge screen
// ─────────────────────────────────────────────────

class RoutineSeriesDoneView extends WatchUi.View {
    private var _session    as WorkoutSession;
    private var _runner     as RoutineRunner;
    private var _completedN as Number;  // 1-based series number just finished

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session    as WorkoutSession,
                        runner     as RoutineRunner,
                        completedN as Number) {
        View.initialize();
        _session    = session;
        _runner     = runner;
        _completedN = completedN;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Série X/N terminée"
        var label = "Série " + _completedN.toString()
                  + "/" + _runner.totalSeries().toString() + " terminée";
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Exercise name
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score
        var score = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 94, Graphics.FONT_NUMBER_MEDIUM, score,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Percentage
        var pct      = _session.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Separator
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(40, 156, w - 40, 156);

        // Next series info or "last series" message
        if (!_runner.isComplete()) {
            var nextName  = getExerciseName(_runner.currentExerciseId());
            var nextShots = _runner.currentTotalShots();
            dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 172, Graphics.FONT_XTINY, "→ " + nextName,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 188, Graphics.FONT_XTINY,
                        "×" + nextShots.toString() + " tirs",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 178, Graphics.FONT_XTINY, "Dernière série !",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instructions
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 209, Graphics.FONT_XTINY,
                    _runner.isComplete() ? "Résumé final" : "▶ Continuer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 228, Graphics.FONT_XTINY, "↩ Abandonner",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineSeriesDoneDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean {
        if (_runner.isComplete()) {
            var view = new RoutineFinalView(_runner);
            var del  = new RoutineFinalDelegate(_runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        } else {
            var sess = new WorkoutSession(_runner.currentExerciseId(), _runner.currentTotalShots());
            var view = new WorkoutView(sess, null);
            var del  = new WorkoutDelegate(sess, view, null, _runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    // BACK = abandon → show final with partial results
    function onBack() as Boolean {
        var view = new RoutineFinalView(_runner);
        var del  = new RoutineFinalDelegate(_runner);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }
}

// ─────────────────────────────────────────────────
// RoutineFinalView — global summary (no re-send needed)
// ─────────────────────────────────────────────────

class RoutineFinalView extends WatchUi.View {
    private var _runner as RoutineRunner;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(runner as RoutineRunner) {
        View.initialize();
        _runner = runner;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w   = dc.getWidth();
        var cx  = w / 2;
        var acc = _runner.accumulator;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "Séance terminée"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, Graphics.FONT_XTINY, "Séance terminée",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "N séries"
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_XTINY,
                    acc.seriesCount().toString() + " séries",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Total score
        var scoreText = acc.totalMade().toString() + " / " + acc.totalShots().toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 94, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Percentage
        var pct      = acc.percentage();
        var pctColor = pct >= 70 ? COLOR_GREEN : (pct >= 50 ? COLOR_ORANGE : COLOR_RED);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Duration
        var elapsed = acc.elapsedSeconds();
        var mins    = elapsed / 60;
        var secs    = elapsed % 60;
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 163, Graphics.FONT_XTINY,
                    mins.format("%d") + "min " + secs.format("%02d") + "s",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // "Terminer" (no send button — each series was already transmitted)
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 208, Graphics.FONT_XTINY, "▶ Terminer",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class RoutineFinalDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as RoutineRunner;

    function initialize(runner as RoutineRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    function onSelect() as Boolean { popToRoot(); return true; }
    function onBack()   as Boolean { popToRoot(); return true; }

    private function popToRoot() as Void {
        // Stack at this point: MainMenu + RoutineStart
        //   + K × (WorkoutView + RoutineSeriesDoneView) + RoutineFinalView
        // Total pops needed = 2K + 2  (K = completed series count)
        var k    = _runner.accumulator.seriesCount();
        var pops = k * 2 + 2;
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
