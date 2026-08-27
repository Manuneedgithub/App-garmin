package com.tonnom.baskettrainer

import android.app.Application
import com.tonnom.baskettrainer.data.SessionRepository

class BasketTrainerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SessionRepository.init(this)
        // GarminManager.init(this) — added in Task 5
    }
}
