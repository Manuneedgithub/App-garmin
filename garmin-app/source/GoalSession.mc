import Toybox.Lang;
import Toybox.Time;

// ─────────────────────────────────────────────────
// Modèle de données pour une session "Objectif"
// L'objectif est un nombre de paniers à rentrer.
// La session s'arrête quand madeShots == targetMade.
// ─────────────────────────────────────────────────
class GoalSession {
    var exerciseId   as Number;
    var exerciseName as String;
    var targetMade   as Number;  // objectif : nombre de paniers à rentrer
    var madeShots    as Number;  // paniers réussis jusqu'ici
    var totalShots   as Number;  // tirs au total (réussis + ratés)
    var results      as Array;   // [Boolean] — true=réussi, false=raté
    var startTime    as Number;  // timestamp Unix
    var shotType     as Number;  // type de tir (Catch & Shoot / Avec dribble / À l'arrêt)

    function initialize(exId as Number, target as Number, shotTypeId as Number) {
        exerciseId   = exId;
        exerciseName = getExerciseName(exId);
        targetMade   = target;
        madeShots    = 0;
        totalShots   = 0;
        results      = new [0];
        startTime    = Time.now().value();
        shotType     = shotTypeId;
    }

    // Enregistre un tir
    function recordShot(made as Boolean) as Void {
        results.add(made);
        totalShots++;
        if (made) { madeShots++; }
    }

    // Vrai quand l'objectif est atteint
    function isGoalReached() as Boolean {
        return madeShots >= targetMade;
    }

    // Pourcentage de réussite (0-100)
    function percentage() as Number {
        if (totalShots == 0) { return 0; }
        return (madeShots * 100) / totalShots;
    }

    // Sérialise pour envoi à l'iPhone
    function toDictionary() as Dictionary {
        return {
            "exerciseId"   => exerciseId,
            "exerciseName" => exerciseName,
            "totalShots"   => totalShots,
            "madeShots"    => madeShots,
            "percentage"   => percentage(),
            "startTime"    => startTime,
            "results"      => results,
            "duration"     => Time.now().value() - startTime,
            "targetMade"   => targetMade,
            "shotTypeId"   => shotType
        };
    }
}
