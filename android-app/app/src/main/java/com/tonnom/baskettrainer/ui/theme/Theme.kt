package com.tonnom.baskettrainer.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val BasketTrainerColorScheme = darkColorScheme(
    primary = AccentOrange,
    background = BackgroundDark,
    surface = SurfaceDark,
    onBackground = OnSurfaceDark,
    onSurface = OnSurfaceDark
)

@Composable
fun BasketTrainerTheme(content: @Composable () -> Unit) {
    // Dark mode forcé — parité avec ios-app (BasketTrainerApp.swift force le dark mode).
    MaterialTheme(colorScheme = BasketTrainerColorScheme, content = content)
}
