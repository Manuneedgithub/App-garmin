import Toybox.Lang;
import Toybox.Time;

// ─────────────────────────────────────────────────
// Accumule plusieurs WorkoutSession (séries) pour
// une séance multi-exercices. Tracke aussi la durée
// globale depuis le début de la première série.
// ─────────────────────────────────────────────────

class SessionAccumulator {
    var completedSeries as Array;   // Array of WorkoutSession
    var globalStartTime as Number;  // timestamp Unix du début de séance

    function initialize() {
        completedSeries = new [0];
        globalStartTime = Time.now().value();
    }

    function addSeries(session as WorkoutSession) as Void {
        completedSeries.add(session);
    }

    function seriesCount() as Number {
        return completedSeries.size();
    }

    function totalShots() as Number {
        var t = 0;
        for (var i = 0; i < completedSeries.size(); i++) {
            t += (completedSeries[i] as WorkoutSession).totalShots;
        }
        return t;
    }

    function totalMade() as Number {
        var m = 0;
        for (var i = 0; i < completedSeries.size(); i++) {
            m += (completedSeries[i] as WorkoutSession).madeShots;
        }
        return m;
    }

    function percentage() as Number {
        var t = totalShots();
        if (t == 0) { return 0; }
        return (totalMade() * 100) / t;
    }

    function elapsedSeconds() as Number {
        return Time.now().value() - globalStartTime;
    }

    // Encode en URL baskettrainer://m?... pour openWebPage()
    // Format : n=nb séries, s0e/s0t/s0m/s0r=série 0, s1e/...=série 1, etc.
    function toURL() as String {
        var n = completedSeries.size();
        var d = elapsedSeconds();
        var url = "baskettrainer://m?st=" + globalStartTime.toString()
                + "&d=" + d.toString()
                + "&n=" + n.toString();
        for (var i = 0; i < n; i++) {
            var s = completedSeries[i] as WorkoutSession;
            var r = "";
            for (var j = 0; j < s.results.size(); j++) {
                r = r + ((s.results[j] as Boolean) ? "1" : "0");
            }
            url = url + "&s" + i.toString() + "e=" + s.exerciseId.toString()
                      + "&s" + i.toString() + "t=" + s.totalShots.toString()
                      + "&s" + i.toString() + "m=" + s.madeShots.toString()
                      + "&s" + i.toString() + "r=" + r;
        }
        return url;
    }

    // Sérialise pour envoi iPhone (format multi)
    function toDictionary() as Dictionary {
        var seriesArr = new [completedSeries.size()];
        for (var i = 0; i < completedSeries.size(); i++) {
            seriesArr[i] = (completedSeries[i] as WorkoutSession).toDictionary();
        }
        return {
            "isMulti"    => true,
            "series"     => seriesArr,
            "totalShots" => totalShots(),
            "madeShots"  => totalMade(),
            "percentage" => percentage(),
            "startTime"  => globalStartTime,
            "duration"   => elapsedSeconds()
        };
    }
}
