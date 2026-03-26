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
