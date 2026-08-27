package com.tonnom.baskettrainer.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val BasketTrainerColorScheme = darkColorScheme(
    primary = AccentOrange,
    onPrimary = Color.White,
    primaryContainer = AccentOrange,
    onPrimaryContainer = Color.White,
    secondaryContainer = AccentOrange.copy(alpha = 0.35f),
    onSecondaryContainer = Color.White,
    background = BackgroundDark,
    surface = SurfaceDark,
    onBackground = OnSurfaceDark,
    onSurface = OnSurfaceDark
)

@Composable
fun BasketTrainerTheme(content: @Composable () -> Unit) {
    // Dark mode forcé — thème de l'app (cf. CLAUDE.md), pas une adaptation au thème système.
    MaterialTheme(colorScheme = BasketTrainerColorScheme, content = content)
}
