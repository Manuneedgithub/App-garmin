package com.tonnom.baskettrainer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.tonnom.baskettrainer.data.SessionRepository
import com.tonnom.baskettrainer.garmin.GarminManager
import com.tonnom.baskettrainer.ui.components.SessionRow

@Composable
fun HomeScreen() {
    val sessions by SessionRepository.sessions.collectAsState()
    val connectedDevice by GarminManager.connectedDevice.collectAsState()
    val garminAvailable by GarminManager.garminConnectAvailable.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Spacer(Modifier.height(10.dp)) }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(12.dp))
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                val statusText = when {
                    !garminAvailable -> "Garmin Connect Mobile indisponible"
                    connectedDevice != null -> "Montre connectée"
                    else -> "Montre non connectée"
                }
                Text(statusText, modifier = Modifier.weight(1f))
                if (garminAvailable && connectedDevice == null) {
                    Button(onClick = { GarminManager.connectWatch() }) { Text("Connecter") }
                }
            }
        }

        item {
            val totalShots = sessions.sumOf { it.totalShots }
            val overallPct = if (totalShots == 0) 0
                else (sessions.sumOf { it.madeShots } * 100) / totalShots
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatCard("${sessions.size}", "Séances", Modifier.weight(1f))
                StatCard("$totalShots", "Tirs", Modifier.weight(1f))
                StatCard("$overallPct%", "Réussite", Modifier.weight(1f))
            }
        }

        item { Text("Récentes", style = MaterialTheme.typography.titleMedium) }

        items(sessions.sortedByDescending { it.date }.take(10), key = { it.id }) { session ->
            SessionRow(session)
        }

        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun StatCard(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge)
        Text(label, style = MaterialTheme.typography.bodySmall)
    }
}
