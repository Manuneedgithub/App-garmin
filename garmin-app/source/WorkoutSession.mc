import Toybox.Lang;
import Toybox.Time;

// ─────────────────────────────────────────────────
// Modèle de données d'une séance
// Partagé entre WorkoutView, WorkoutDelegate et SummaryView
// ─────────────────────────────────────────────────
class WorkoutSession {
    var exerciseId   as Number;
    var exerciseName as String;
    var totalShots   as Number;
    var currentShot  as Number;  // index du tir en cours (0-based)
    var madeShots    as Number;
    var results      as Array;   // tableau de Boolean : true=réussi, false=raté
    var startTime    as Number;  // timestamp Unix

    function initialize(exId as Number, total as Number) {
        exerciseId   = exId;
        exerciseName = getExerciseName(exId);
        totalShots   = total;
        currentShot  = 0;
        madeShots    = 0;
        results      = new [0];
        startTime    = Time.now().value();
    }

    // Enregistre un tir et avance le compteur
    function recordShot(made as Boolean) as Void {
        results.add(made);
        if (made) { madeShots++; }
        currentShot++;
    }

    // Vrai si tous les tirs ont été enregistrés
    function isFinished() as Boolean {
        return currentShot >= totalShots;
    }

    // Pourcentage de réussite (0-100)
    function percentage() as Number {
        if (currentShot == 0) { return 0; }
        return (madeShots * 100) / currentShot;
    }

    // Sérialise la session pour l'envoi à l'iPhone
    // duration = temps écoulé depuis startTime au moment de l'envoi
    function toDictionary() as Dictionary {
        return {
            "exerciseId"   => exerciseId,
            "exerciseName" => exerciseName,
            "totalShots"   => totalShots,
            "madeShots"    => madeShots,
            "percentage"   => percentage(),
            "startTime"    => startTime,
            "results"      => results,
            "duration"     => Time.now().value() - startTime
        };
    }
}
