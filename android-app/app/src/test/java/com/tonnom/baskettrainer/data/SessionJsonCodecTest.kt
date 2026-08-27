// android-app/app/src/test/java/com/tonnom/baskettrainer/data/SessionJsonCodecTest.kt
package com.tonnom.baskettrainer.data

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.WorkoutSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionJsonCodecTest {

    @Test
    fun `round trip preserves session fields`() {
        val session = WorkoutSession(
            id = "abc123",
            exerciseType = ExerciseType.THREE_CENTER,
            totalShots = 10,
            madeShots = 7,
            results = listOf(true, true, false, true, true, false, true, false, true, true),
            date = 1_700_000_000_000L,
            sentFromWatch = true,
            series = null,
            duration = 320L,
            shotType = null
        )

        val encoded = SessionJsonCodec.encode(listOf(session))
        val decoded = SessionJsonCodec.decode(encoded)

        assertEquals(1, decoded.size)
        assertEquals(session, decoded.first())
    }

    @Test
    fun `decode returns empty list for corrupted json`() {
        assertTrue(SessionJsonCodec.decode("not valid json").isEmpty())
    }

    @Test
    fun `decode returns empty list for null input`() {
        assertTrue(SessionJsonCodec.decode(null).isEmpty())
    }
}
