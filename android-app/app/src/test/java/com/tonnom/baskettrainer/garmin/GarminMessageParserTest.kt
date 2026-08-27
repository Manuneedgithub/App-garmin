package com.tonnom.baskettrainer.garmin

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.ShotType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GarminMessageParserTest {

    // Matches the keys WorkoutSession.mc#toDictionary() actually sends.
    private fun baseWatchPayload(): Map<String, Any?> = mapOf(
        "exerciseId" to 6,
        "exerciseName" to "Mi-distance Centre",
        "totalShots" to 10,
        "madeShots" to 7,
        "percentage" to 70,
        "startTime" to 1_700_000_000,
        "results" to listOf(true, true, false, true, true, false, true, false, true, true),
        "duration" to 245,
        "shotTypeId" to 1
    )

    @Test
    fun `parses a simple session`() {
        val session = GarminMessageParser.parse(baseWatchPayload())

        assertEquals(ExerciseType.MID_CENTER, session.exerciseType)
        assertEquals(10, session.totalShots)
        assertEquals(7, session.madeShots)
        assertEquals(1_700_000_000_000L, session.date)
        assertEquals(245L, session.duration)
        assertEquals(ShotType.OFF_DRIBBLE, session.shotType)
        assertEquals(true, session.sentFromWatch)
        assertNull(session.series)
    }

    @Test
    fun `a targetMade field produces a single-entry series with that target`() {
        val payload = baseWatchPayload() + mapOf("targetMade" to 8)

        val session = GarminMessageParser.parse(payload)

        assertEquals(1, session.series?.size)
        val series = session.series!!.first()
        assertEquals(ExerciseType.MID_CENTER, series.exerciseType)
        assertEquals(8, series.targetMade)
        assertEquals(10, series.totalShots)
        assertEquals(7, series.madeShots)
    }

    @Test
    fun `missing optional fields fall back to safe defaults`() {
        val session = GarminMessageParser.parse(mapOf("exerciseId" to 0))

        assertEquals(ExerciseType.FREETHROW, session.exerciseType)
        assertEquals(0, session.totalShots)
        assertEquals(0, session.madeShots)
        assertEquals(emptyList<Boolean>(), session.results)
        assertNull(session.shotType)
        assertNull(session.duration)
        assertNull(session.series)
    }
}
