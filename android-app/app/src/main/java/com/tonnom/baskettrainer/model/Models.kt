package com.tonnom.baskettrainer.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class ExerciseType(val id: Int, val builtInName: String, val builtInEmoji: String) {
    FREETHROW(0, "Lancer Franc", "🎯"),
    THREE_CENTER(1, "3pts Centre", "🏀"),
    THREE_RIGHT_45(2, "3pts 45° Droite", "↗️"),
    THREE_LEFT_45(3, "3pts 45° Gauche", "↗️"),
    THREE_CORNER_R(4, "3pts Coin Droite", "📐"),
    THREE_CORNER_L(5, "3pts Coin Gauche", "📐"),
    MID_CENTER(6, "Mi-distance Centre", "🎳"),
    MID_RIGHT(7, "Mi-distance Droite", "🎳"),
    MID_LEFT(8, "Mi-distance Gauche", "🎳"),
    FLOATER(9, "Flotteur", "🪶"),
    FORM_SHOT_SIDE_TO_SIDE(10, "Form Shot Side to Side", "↔️"),
    // Réservé aux spots personnalisés (créés côté iOS pour l'instant — cf. sous-projet 2
    // pour l'écran Android équivalent). On garde les ids 11-15 ici pour ne pas mal
    // décoder une séance envoyée par la montre qui référence un spot custom.
    CUSTOM_1(11, "Spot personnalisé", "📍"),
    CUSTOM_2(12, "Spot personnalisé", "📍"),
    CUSTOM_3(13, "Spot personnalisé", "📍"),
    CUSTOM_4(14, "Spot personnalisé", "📍"),
    CUSTOM_5(15, "Spot personnalisé", "📍");

    companion object {
        fun fromId(id: Int): ExerciseType = entries.firstOrNull { it.id == id } ?: FREETHROW
    }
}

@Serializable
enum class ShotType(val id: Int, val label: String) {
    CATCH_AND_SHOOT(0, "Catch & Shoot"),
    OFF_DRIBBLE(1, "Avec dribble"),
    STANDING(2, "À l'arrêt");

    companion object {
        fun fromId(id: Int): ShotType? = entries.firstOrNull { it.id == id }
    }
}

@Serializable
data class ShotSeries(
    val id: String = UUID.randomUUID().toString(),
    val exerciseType: ExerciseType,
    val totalShots: Int,
    val madeShots: Int,
    val results: List<Boolean> = emptyList(),
    val targetMade: Int? = null,
    val shotType: ShotType? = null
) {
    val percentage: Double get() = if (totalShots == 0) 0.0 else madeShots.toDouble() / totalShots * 100
    val missedShots: Int get() = totalShots - madeShots
}

@Serializable
data class WorkoutSession(
    val id: String = UUID.randomUUID().toString(),
    val exerciseType: ExerciseType,
    val totalShots: Int,
    val madeShots: Int,
    val results: List<Boolean> = emptyList(),
    val date: Long,                    // epoch millis
    val sentFromWatch: Boolean = false,
    val series: List<ShotSeries>? = null,
    val duration: Long? = null,        // seconds
    val shotType: ShotType? = null
) {
    val isComplex: Boolean get() = (series?.size ?: 0) > 1
    val missedShots: Int get() = totalShots - madeShots
    val percentage: Double get() = if (totalShots == 0) 0.0 else madeShots.toDouble() / totalShots * 100
    val displayName: String
        get() = series?.let { if (it.size > 1) "Séance complexe (${it.size} séries)" else null }
            ?: exerciseType.builtInName
    val displayEmoji: String get() = if (isComplex) "🗂️" else exerciseType.builtInEmoji
}
