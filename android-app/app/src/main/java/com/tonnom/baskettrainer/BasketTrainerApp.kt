package com.tonnom.baskettrainer

import android.app.Application

class BasketTrainerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // SessionRepository.init(this) — added in Task 4
        // GarminManager.init(this) — added in Task 5
    }
}
