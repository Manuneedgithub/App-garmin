package com.tonnom.baskettrainer.model

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsTest {

    @Test
    fun `fromId resolves every built-in and custom id 0 through 15`() {
        val expected = listOf(
            0 to ExerciseType.FREETHROW, 1 to ExerciseType.THREE_CENTER,
            2 to ExerciseType.THREE_RIGHT_45, 3 to ExerciseType.THREE_LEFT_45,
            4 to ExerciseType.THREE_CORNER_R, 5 to ExerciseType.THREE_CORNER_L,
            6 to ExerciseType.MID_CENTER, 7 to ExerciseType.MID_RIGHT,
            8 to ExerciseType.MID_LEFT, 9 to ExerciseType.FLOATER,
            10 to ExerciseType.FORM_SHOT_SIDE_TO_SIDE, 11 to ExerciseType.CUSTOM_1,
            12 to ExerciseType.CUSTOM_2, 13 to ExerciseType.CUSTOM_3,
            14 to ExerciseType.CUSTOM_4, 15 to ExerciseType.CUSTOM_5
        )
        expected.forEach { (id, type) -> assertEquals(type, ExerciseType.fromId(id)) }
    }

    @Test
    fun `fromId falls back to FREETHROW for an unknown id`() {
        assertEquals(ExerciseType.FREETHROW, ExerciseType.fromId(99))
    }

    @Test
    fun `WorkoutSession percentage is zero when totalShots is zero`() {
        val session = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW,
            totalShots = 0,
            madeShots = 0,
            date = 0L
        )
        assertEquals(0.0, session.percentage, 0.0001)
    }

    @Test
    fun `WorkoutSession percentage divides madeShots by totalShots`() {
        val session = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW,
            totalShots = 10,
            madeShots = 7,
            date = 0L
        )
        assertEquals(70.0, session.percentage, 0.0001)
    }

    @Test
    fun `isComplex is true only when series has more than one entry`() {
        val single = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3, date = 0L,
            series = listOf(ShotSeries(exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3))
        )
        val multi = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3, date = 0L,
            series = listOf(
                ShotSeries(exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3),
                ShotSeries(exerciseType = ExerciseType.MID_CENTER, totalShots = 5, madeShots = 2)
            )
        )
        assertEquals(false, single.isComplex)
        assertEquals(true, multi.isComplex)
    }
}
