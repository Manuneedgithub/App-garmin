package com.tonnom.baskettrainer.data

import com.tonnom.baskettrainer.model.WorkoutSession
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object SessionJsonCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun encode(sessions: List<WorkoutSession>): String = json.encodeToString(sessions)

    fun decode(raw: String?): List<WorkoutSession> {
        if (raw == null) return emptyList()
        return try {
            json.decodeFromString(raw)
        } catch (e: Exception) {
            emptyList()
        }
    }
}
