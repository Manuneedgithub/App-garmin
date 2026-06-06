import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// Écran de sélection de l'objectif paniers
//
//   ┌──────────────────────────┐
//   │     Lancer Franc         │  titre exercice
//   │  Objectif : 10 paniers   │  valeur courante
//   │                          │
//   │  5  10  15  20  25  30   │  chips rapides
//   │                          │
//   │  ▲ +1     ▼ -1           │
//   │  SELECT pour valider     │
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalMenuView extends WatchUi.View {
    private var _exerciseId as Number;
    private var _target     as Number;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize(exerciseId as Number, initialTarget as Number) {
        View.initialize();
        _exerciseId = exerciseId;
        _target     = initialTarget;
    }

    function setTarget(t as Number) as Void {
        _target = t;
        WatchUi.requestUpdate();
    }

    function getTarget() as Number {
        return _target;
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
        dc.drawText(cx, 30, Graphics.FONT_XTINY, getExerciseName(_exerciseId),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif courant
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90, Graphics.FONT_NUMBER_MEDIUM, _target.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 130, Graphics.FONT_TINY, "paniers",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Chips rapides
        var chips = [5, 10, 15, 20, 25, 30];
        var chipW = w / chips.size();
        for (var i = 0; i < chips.size(); i++) {
            var chip = chips[i] as Number;
            var cx2  = (i * chipW) + chipW / 2;
            var col  = (chip == _target) ? COLOR_ORANGE : COLOR_GRAY;
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx2, 178, Graphics.FONT_XTINY, chip.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 52, 220, Graphics.FONT_XTINY, "\u2191 +1",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 52, 220, Graphics.FONT_XTINY, "\u2193 -1",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 240, Graphics.FONT_XTINY, "START = valider",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class GoalMenuDelegate extends WatchUi.BehaviorDelegate {
    private var _view       as GoalMenuView;
    private var _exerciseId as Number;
    private var _shotTypeId as Number;

    function initialize(view as GoalMenuView, exerciseId as Number, shotTypeId as Number) {
        BehaviorDelegate.initialize();
        _view       = view;
        _exerciseId = exerciseId;
        _shotTypeId = shotTypeId;
    }

    // Bouton HAUT → +1
    function onNextPage() as Boolean {
        var t = _view.getTarget() + 1;
        if (t > 50) { t = 50; }
        _view.setTarget(t);
        return true;
    }

    // Bouton BAS → -1
    function onPreviousPage() as Boolean {
        var t = _view.getTarget() - 1;
        if (t < 1) { t = 1; }
        _view.setTarget(t);
        return true;
    }

    // SELECT → lancer la session
    function onSelect() as Boolean {
        var session = new GoalSession(_exerciseId, _view.getTarget(), _shotTypeId);
        var view    = new GoalView(session);
        var del     = new GoalDelegate(session, view);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
