package com.tonnom.baskettrainer.garmin

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.ShotSeries
import com.tonnom.baskettrainer.model.ShotType
import com.tonnom.baskettrainer.model.WorkoutSession

object GarminMessageParser {

    fun parse(dict: Map<*, *>): WorkoutSession {
        val exerciseId = (dict["exerciseId"] as? Number)?.toInt() ?: 0
        val exerciseType = ExerciseType.fromId(exerciseId)
        val totalShots = (dict["totalShots"] as? Number)?.toInt() ?: 0
        val madeShots = (dict["madeShots"] as? Number)?.toInt() ?: 0
        val startTime = (dict["startTime"] as? Number)?.toLong() ?: 0L
        val duration = (dict["duration"] as? Number)?.toLong()
        @Suppress("UNCHECKED_CAST")
        val results = (dict["results"] as? List<Boolean>) ?: emptyList()
        val targetMade = (dict["targetMade"] as? Number)?.toInt()
        val shotType = (dict["shotTypeId"] as? Number)?.toInt()?.let { ShotType.fromId(it) }

        val series = targetMade?.let {
            listOf(
                ShotSeries(
                    exerciseType = exerciseType,
                    totalShots = totalShots,
                    madeShots = madeShots,
                    results = results,
                    targetMade = it,
                    shotType = shotType
                )
            )
        }

        return WorkoutSession(
            exerciseType = exerciseType,
            totalShots = totalShots,
            madeShots = madeShots,
            results = results,
            date = startTime * 1000,
            sentFromWatch = true,
            series = series,
            duration = duration,
            shotType = shotType
        )
    }
}
