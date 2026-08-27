package com.tonnom.baskettrainer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.tonnom.baskettrainer.model.WorkoutSession
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun SessionRow(session: WorkoutSession, modifier: Modifier = Modifier) {
    val dateFormat = remember(session.id) { SimpleDateFormat("dd/MM HH:mm", Locale.FRANCE) }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(session.displayEmoji, modifier = Modifier.padding(end = 12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(session.displayName, style = MaterialTheme.typography.titleSmall)
            Text(
                dateFormat.format(Date(session.date)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("${session.madeShots}/${session.totalShots}", style = MaterialTheme.typography.titleSmall)
            val pctColor = when {
                session.percentage >= 70 -> Color(0xFF33CC66)
                session.percentage >= 50 -> Color(0xFFFF9800)
                else -> Color(0xFFFF3333)
            }
            Text("${session.percentage.toInt()}%", color = pctColor, style = MaterialTheme.typography.bodySmall)
        }
    }
}
