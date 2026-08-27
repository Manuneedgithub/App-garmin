package com.tonnom.baskettrainer.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.tonnom.baskettrainer.model.WorkoutSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private val Context.dataStore by preferencesDataStore(name = "basket_sessions_store")

object SessionRepository {
    private val SESSIONS_KEY = stringPreferencesKey("basket_sessions")

    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))

    private val _sessions = MutableStateFlow<List<WorkoutSession>>(emptyList())
    val sessions: StateFlow<List<WorkoutSession>> get() = _sessions

    private var loadJob: Job? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        loadJob = scope.launch {
            val raw = appContext.dataStore.data.first()[SESSIONS_KEY]
            _sessions.value = SessionJsonCodec.decode(raw)
        }
    }

    fun add(session: WorkoutSession) {
        scope.launch {
            loadJob?.join()
            val updated = _sessions.value + session
            _sessions.value = updated
            persist(updated)
        }
    }

    fun delete(sessionId: String) {
        scope.launch {
            loadJob?.join()
            val updated = _sessions.value.filterNot { it.id == sessionId }
            _sessions.value = updated
            persist(updated)
        }
    }

    private suspend fun persist(sessions: List<WorkoutSession>) {
        val raw = SessionJsonCodec.encode(sessions)
        appContext.dataStore.edit { it[SESSIONS_KEY] = raw }
    }
}
