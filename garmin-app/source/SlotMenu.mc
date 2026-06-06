import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Application;

// Returns "X séries · Y tirs" if slot has data, null if empty
function slotSummary(index as Number) as String or Null {
    var val = Application.Storage.getValue("slot_" + index.toString());
    if (val == null) { return null; }
    var arr   = val as Array;
    var total = 0;
    for (var i = 0; i < arr.size(); i++) {
        total += (arr[i] as Dictionary)["totalShots"] as Number;
    }
    return arr.size().toString() + " séries · " + total.toString() + " tirs";
}

class SlotMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Entraînements"});
        for (var i = 0; i < 5; i++) {
            var label = "Entr. " + (i + 1).toString();
            var sub   = slotSummary(i);
            addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
    }
}

class SlotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index  = item.getId() as Number;
        var series = Application.Storage.getValue("slot_" + index.toString());
        if (series == null) {
            WatchUi.pushView(new SlotEmptyView(), new SlotEmptyDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            var routine = {"series" => series as Array} as Dictionary;
            var runner  = new RoutineRunner(routine);
            var view    = new RoutineStartView(runner);
            var del     = new RoutineStartDelegate(runner);
            WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class SlotEmptyView extends WatchUi.View {
    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize() { View.initialize(); }
    function onLayout(dc as Graphics.Dc) as Void {}

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();
        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90, Graphics.FONT_TINY, "Slot vide",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 118, Graphics.FONT_XTINY, "Configure depuis",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 136, Graphics.FONT_XTINY, "l'app iPhone",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 215, Graphics.FONT_XTINY, "↩ Retour",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class SlotEmptyDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
