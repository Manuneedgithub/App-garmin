package com.tonnom.baskettrainer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.tonnom.baskettrainer.data.SessionRepository
import com.tonnom.baskettrainer.model.WorkoutSession
import com.tonnom.baskettrainer.ui.components.SessionRow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun HistoryScreen() {
    val sessions by SessionRepository.sessions.collectAsState()
    val grouped = sessions
        .sortedByDescending { it.date }
        .groupBy { dayLabel(it.date) }

    if (sessions.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Aucune séance pour l'instant.")
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { Spacer(Modifier.height(10.dp)) }
        grouped.forEach { (day, daySessions) ->
            item {
                Text(
                    day,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                )
            }
            items(daySessions, key = { it.id }) { session ->
                HistoryRow(session, onDelete = { SessionRepository.delete(session.id) })
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun HistoryRow(session: WorkoutSession, onDelete: () -> Unit) {
    var showConfirm by remember { mutableStateOf(false) }

    Row(verticalAlignment = Alignment.CenterVertically) {
        SessionRow(session, modifier = Modifier.weight(1f))
        IconButton(onClick = { showConfirm = true }) {
            Icon(Icons.Default.Delete, contentDescription = "Supprimer")
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Supprimer cette séance ?") },
            text = { Text("Cette action est irréversible.") },
            confirmButton = {
                TextButton(onClick = { showConfirm = false; onDelete() }) { Text("Supprimer") }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text("Annuler") }
            }
        )
    }
}

private fun dayLabel(epochMillis: Long): String =
    SimpleDateFormat("EEEE d MMMM", Locale.FRANCE).format(Date(epochMillis))
        .replaceFirstChar { it.uppercase() }
