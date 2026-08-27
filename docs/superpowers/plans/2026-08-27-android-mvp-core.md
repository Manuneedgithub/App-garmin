# Android MVP Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a native Android app (Kotlin + Jetpack Compose) that receives a shooting session transmitted by the Forerunner 255 via the Connect IQ Mobile SDK, persists it, and shows it in an Accueil (Home) + Historique (History) UI — the Android counterpart of `ios-app/BasketTrainer`'s core flow.

**Architecture:** Single-module Android app (`android-app/app`). A `model` package holds plain Kotlin data classes (portage of `Models.swift`) serialized with `kotlinx.serialization`. A `data` package holds a pure JSON codec (unit-tested) plus a `SessionRepository` singleton wrapping it in Jetpack DataStore, exposed as a `StateFlow`. A `garmin` package holds `GarminManager` (Connect IQ SDK device/session lifecycle) and a pure `GarminMessageParser` (unit-tested) that turns a raw watch payload into a `WorkoutSession`. A `ui` package holds two Compose screens (Home, History) wired together by `MainActivity`'s bottom-nav `NavHost`.

**Tech Stack:** Kotlin 2.0.21, Jetpack Compose (BOM 2025.12.00, Material3), AGP 8.6.0, Connect IQ Mobile SDK for Android (`com.garmin.connectiq:ciq-companion-app-sdk:2.4.0`, Maven Central), Jetpack DataStore Preferences 1.1.1, kotlinx.serialization 1.7.3, kotlinx.coroutines 1.9.0, Navigation Compose 2.8.4, JUnit 4.13.2.

**Spec:** `docs/superpowers/specs/2026-08-26-android-mvp-core-design.md`

## Global Constraints

- Package / applicationId: `com.tonnom.baskettrainer` (matches the iOS bundle ID)
- minSdk 26, compileSdk 35, targetSdk 35
- Garmin app UUID (must match `garmin-app/manifest.xml` and `ios-app/BasketTrainer/Managers/GarminManager.swift` exactly): `a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a`
- Native Kotlin/Compose only — no Kotlin Multiplatform, no Flutter
- Out of scope for this plan (deferred to later sub-projects): Terrain/spots screen, custom spots, Stats screen/charts, manual session entry, session editing, watch slots. Do not add UI entry points for any of these.
- **Deviation from the spec, verified during planning:** the spec assumed Android 12+ would need runtime Bluetooth permissions (`BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN`) and planned an error state for a denied permission. Checking Garmin's own current `connectiq-android-sdk` sample app (fetched during planning) shows its manifest requests only `INTERNET` — the Connect IQ SDK talks to Garmin Connect Mobile through a bound service, not the Android Bluetooth APIs directly, so the app itself never needs Bluetooth permissions or a denied-permission fallback. This plan follows the verified reality instead of the spec's assumption; no task below handles a Bluetooth permission prompt.
- No automated UI/instrumentation test infra in this repo (mirrors `ios-app`, which has none) — only pure-logic unit tests (JUnit, JVM, no device/emulator) plus explicit manual-QA checklists for anything touching Compose UI or the Connect IQ SDK, which cannot be exercised from this environment. Steps marked **[MANUAL — physical device required]** must be performed by a human with the Android phone and paired Forerunner 255; they cannot be completed by an agent running in this sandbox.

---

## File Structure

```
android-app/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── app/
│   ├── build.gradle.kts
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   └── java/com/tonnom/baskettrainer/
│       │       ├── MainActivity.kt              (Task 1 skeleton, rewired in Task 8)
│       │       ├── BasketTrainerApp.kt           (Application; init calls added in Tasks 4 & 5)
│       │       ├── model/Models.kt               (Task 2)
│       │       ├── data/SessionJsonCodec.kt      (Task 3)
│       │       ├── data/SessionRepository.kt     (Task 4)
│       │       ├── garmin/GarminManager.kt       (Task 5, extended Task 6)
│       │       ├── garmin/GarminMessageParser.kt (Task 6)
│       │       ├── ui/theme/Color.kt             (Task 7)
│       │       ├── ui/theme/Theme.kt             (Task 7)
│       │       ├── ui/components/SessionRow.kt   (Task 7)
│       │       ├── ui/HomeScreen.kt              (Task 7)
│       │       └── ui/HistoryScreen.kt           (Task 8)
│       └── test/java/com/tonnom/baskettrainer/
│           ├── model/ModelsTest.kt               (Task 2)
│           ├── data/SessionJsonCodecTest.kt       (Task 3)
│           └── garmin/GarminMessageParserTest.kt (Task 6)
```

---

### Task 1: Project skeleton

**Files:**
- Create: `android-app/settings.gradle.kts`
- Create: `android-app/build.gradle.kts`
- Create: `android-app/gradle.properties`
- Create: `android-app/app/build.gradle.kts`
- Create: `android-app/app/src/main/AndroidManifest.xml`
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/MainActivity.kt`
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/BasketTrainerApp.kt`
- Create: `android-app/app/src/main/res/values/strings.xml`
- Create: `android-app/app/src/main/res/values/themes.xml`

**Interfaces:**
- Produces: a buildable, launchable empty Compose app. `BasketTrainerApp` (Application subclass, empty `onCreate` body for now) is the file every later task's initialization code lands in.

- [ ] **Step 1: Create the Gradle wrapper**

Gradle must already be installed to bootstrap the wrapper (the wrapper jar itself is a binary file we can't hand-author). Check for it, install via Homebrew if missing, then generate the wrapper:

```bash
mkdir -p /Users/manu/Documents/GitHub/App-garmin/android-app
cd /Users/manu/Documents/GitHub/App-garmin/android-app
which gradle || brew install gradle
gradle wrapper --gradle-version 8.9
```

Expected: `gradlew`, `gradlew.bat`, and `gradle/wrapper/gradle-wrapper.{jar,properties}` now exist under `android-app/`.

- [ ] **Step 2: Create `settings.gradle.kts`**

```kotlin
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "BasketTrainer"
include(":app")
```

- [ ] **Step 3: Create the root `build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application") version "8.6.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}
```

- [ ] **Step 4: Create `gradle.properties`**

```properties
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=true
kotlin.code.style=official
```

- [ ] **Step 5: Create `app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.tonnom.baskettrainer"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.tonnom.baskettrainer"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.12.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 6: Create the manifest**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:name=".BasketTrainerApp"
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="@style/Theme.BasketTrainer">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@style/Theme.BasketTrainer">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>

</manifest>
```

(The `INTERNET` permission matches Garmin's own Comm Android sample manifest — the Connect IQ SDK talks to Garmin Connect Mobile through a bound service, not raw Bluetooth APIs, so no Bluetooth runtime permission is needed here.)

- [ ] **Step 7: Create `res/values/strings.xml` and `res/values/themes.xml`**

```xml
<!-- android-app/app/src/main/res/values/strings.xml -->
<resources>
    <string name="app_name">Basket Trainer</string>
</resources>
```

```xml
<!-- android-app/app/src/main/res/values/themes.xml -->
<resources>
    <style name="Theme.BasketTrainer" parent="android:Theme.Material.NoActionBar" />
</resources>
```

- [ ] **Step 8: Create `BasketTrainerApp.kt`**

```kotlin
package com.tonnom.baskettrainer

import android.app.Application

class BasketTrainerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // SessionRepository.init(this) — added in Task 4
        // GarminManager.init(this) — added in Task 5
    }
}
```

- [ ] **Step 9: Create `MainActivity.kt`**

```kotlin
package com.tonnom.baskettrainer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Text("Basket Trainer")
                }
            }
        }
    }
}
```

- [ ] **Step 10: Build**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`, producing `app/build/outputs/apk/debug/app-debug.apk`.

- [ ] **Step 11: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): scaffold Kotlin/Compose project skeleton"
```

---

### Task 2: Data models

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/model/Models.kt`
- Create: `android-app/app/src/test/java/com/tonnom/baskettrainer/model/ModelsTest.kt`
- Modify: `android-app/app/build.gradle.kts` — add the serialization plugin and dependency

**Interfaces:**
- Consumes: nothing (leaf module)
- Produces: `ExerciseType` (enum, `id: Int` 0-15, `builtInName: String`, `builtInEmoji: String`, `ExerciseType.fromId(id: Int): ExerciseType`), `ShotType` (enum, `id: Int`, `label: String`, `ShotType.fromId(id: Int): ShotType?`), `ShotSeries` (data class), `WorkoutSession` (data class with `isComplex`, `missedShots`, `percentage`, `displayName`, `displayEmoji` computed properties) — all `@Serializable`. Later tasks (3, 4, 6, 7, 8) depend on these exact names.

- [ ] **Step 1: Add the serialization plugin and dependency**

Modify `android-app/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21"
}
```

Add to `dependencies { ... }`:

```kotlin
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
```

- [ ] **Step 2: Write the failing test**

```kotlin
// android-app/app/src/test/java/com/tonnom/baskettrainer/model/ModelsTest.kt
package com.tonnom.baskettrainer.model

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsTest {

    @Test
    fun `fromId resolves every built-in and custom id 0 through 15`() {
        val expected = listOf(
            0 to ExerciseType.FREETHROW, 1 to ExerciseType.THREE_CENTER,
            2 to ExerciseType.THREE_RIGHT_45, 3 to ExerciseType.THREE_LEFT_45,
            4 to ExerciseType.THREE_CORNER_R, 5 to ExerciseType.THREE_CORNER_L,
            6 to ExerciseType.MID_CENTER, 7 to ExerciseType.MID_RIGHT,
            8 to ExerciseType.MID_LEFT, 9 to ExerciseType.FLOATER,
            10 to ExerciseType.FORM_SHOT_SIDE_TO_SIDE, 11 to ExerciseType.CUSTOM_1,
            12 to ExerciseType.CUSTOM_2, 13 to ExerciseType.CUSTOM_3,
            14 to ExerciseType.CUSTOM_4, 15 to ExerciseType.CUSTOM_5
        )
        expected.forEach { (id, type) -> assertEquals(type, ExerciseType.fromId(id)) }
    }

    @Test
    fun `fromId falls back to FREETHROW for an unknown id`() {
        assertEquals(ExerciseType.FREETHROW, ExerciseType.fromId(99))
    }

    @Test
    fun `WorkoutSession percentage is zero when totalShots is zero`() {
        val session = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW,
            totalShots = 0,
            madeShots = 0,
            date = 0L
        )
        assertEquals(0.0, session.percentage, 0.0001)
    }

    @Test
    fun `WorkoutSession percentage divides madeShots by totalShots`() {
        val session = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW,
            totalShots = 10,
            madeShots = 7,
            date = 0L
        )
        assertEquals(70.0, session.percentage, 0.0001)
    }

    @Test
    fun `isComplex is true only when series has more than one entry`() {
        val single = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3, date = 0L,
            series = listOf(ShotSeries(exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3))
        )
        val multi = WorkoutSession(
            exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3, date = 0L,
            series = listOf(
                ShotSeries(exerciseType = ExerciseType.FREETHROW, totalShots = 5, madeShots = 3),
                ShotSeries(exerciseType = ExerciseType.MID_CENTER, totalShots = 5, madeShots = 2)
            )
        )
        assertEquals(false, single.isComplex)
        assertEquals(true, multi.isComplex)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.model.ModelsTest"
```

Expected: FAIL — `Models.kt` does not exist yet, compilation error.

- [ ] **Step 4: Write `Models.kt`**

```kotlin
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
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.model.ModelsTest"
```

Expected: PASS, all 5 tests green.

- [ ] **Step 6: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): add WorkoutSession/ExerciseType data models"
```

---

### Task 3: Session JSON codec

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/data/SessionJsonCodec.kt`
- Create: `android-app/app/src/test/java/com/tonnom/baskettrainer/data/SessionJsonCodecTest.kt`

**Interfaces:**
- Consumes: `com.tonnom.baskettrainer.model.WorkoutSession` (Task 2)
- Produces: `SessionJsonCodec.encode(sessions: List<WorkoutSession>): String`, `SessionJsonCodec.decode(raw: String?): List<WorkoutSession>` (never throws — returns `emptyList()` on any decode failure). Task 4's `SessionRepository` depends on both.

- [ ] **Step 1: Write the failing tests**

```kotlin
// android-app/app/src/test/java/com/tonnom/baskettrainer/data/SessionJsonCodecTest.kt
package com.tonnom.baskettrainer.data

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.WorkoutSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionJsonCodecTest {

    @Test
    fun `round trip preserves session fields`() {
        val session = WorkoutSession(
            id = "abc123",
            exerciseType = ExerciseType.THREE_CENTER,
            totalShots = 10,
            madeShots = 7,
            results = listOf(true, true, false, true, true, false, true, false, true, true),
            date = 1_700_000_000_000L,
            sentFromWatch = true,
            series = null,
            duration = 320L,
            shotType = null
        )

        val encoded = SessionJsonCodec.encode(listOf(session))
        val decoded = SessionJsonCodec.decode(encoded)

        assertEquals(1, decoded.size)
        assertEquals(session, decoded.first())
    }

    @Test
    fun `decode returns empty list for corrupted json`() {
        assertTrue(SessionJsonCodec.decode("not valid json").isEmpty())
    }

    @Test
    fun `decode returns empty list for null input`() {
        assertTrue(SessionJsonCodec.decode(null).isEmpty())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.data.SessionJsonCodecTest"
```

Expected: FAIL — `SessionJsonCodec` does not exist yet.

- [ ] **Step 3: Write `SessionJsonCodec.kt`**

```kotlin
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.data.SessionJsonCodecTest"
```

Expected: PASS, all 3 tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): add pure JSON codec for WorkoutSession list"
```

---

### Task 4: SessionRepository (DataStore persistence)

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/data/SessionRepository.kt`
- Modify: `android-app/app/build.gradle.kts` — add DataStore + coroutines-android dependencies
- Modify: `android-app/app/src/main/java/com/tonnom/baskettrainer/BasketTrainerApp.kt` — call `SessionRepository.init(this)`

**Interfaces:**
- Consumes: `SessionJsonCodec.encode/decode` (Task 3), `WorkoutSession` (Task 2)
- Produces: `SessionRepository.init(context: Context)`, `SessionRepository.sessions: StateFlow<List<WorkoutSession>>`, `SessionRepository.add(session: WorkoutSession)`, `SessionRepository.delete(sessionId: String)`. Tasks 6, 7, 8 depend on these names. Aggregate figures (total shots, overall %) are deliberately *not* exposed here — Task 7 derives them from the already-collected `sessions` state inside the composable, so Compose recomposes correctly when it changes (a property read outside of `collectAsState()` wouldn't reliably trigger recomposition).

No automated test for this task — DataStore's actual file I/O behind a real `Context` is exercised for real starting Task 9's end-to-end manual QA (add a session via the watch, relaunch the app, confirm it's still there). The pure encode/decode logic it delegates to is already covered by Task 3.

- [ ] **Step 1: Add dependencies**

Modify `android-app/app/build.gradle.kts`, add to `dependencies { ... }`:

```kotlin
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
```

- [ ] **Step 2: Write `SessionRepository.kt`**

```kotlin
package com.tonnom.baskettrainer.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.tonnom.baskettrainer.model.WorkoutSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private val Context.dataStore by preferencesDataStore(name = "basket_sessions_store")

object SessionRepository {
    private val SESSIONS_KEY = stringPreferencesKey("basket_sessions")

    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _sessions = MutableStateFlow<List<WorkoutSession>>(emptyList())
    val sessions: StateFlow<List<WorkoutSession>> get() = _sessions

    fun init(context: Context) {
        appContext = context.applicationContext
        scope.launch {
            val raw = appContext.dataStore.data.first()[SESSIONS_KEY]
            _sessions.value = SessionJsonCodec.decode(raw)
        }
    }

    fun add(session: WorkoutSession) {
        scope.launch {
            val updated = _sessions.value + session
            _sessions.value = updated
            persist(updated)
        }
    }

    fun delete(sessionId: String) {
        scope.launch {
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
```

- [ ] **Step 3: Wire it into `BasketTrainerApp`**

Modify `android-app/app/src/main/java/com/tonnom/baskettrainer/BasketTrainerApp.kt`:

```kotlin
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
```

- [ ] **Step 4: Build to confirm it compiles**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): add SessionRepository backed by DataStore"
```

---

### Task 5: GarminManager — SDK setup and device connection

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/garmin/GarminManager.kt`
- Modify: `android-app/app/build.gradle.kts` — add the Connect IQ SDK dependency
- Modify: `android-app/app/src/main/java/com/tonnom/baskettrainer/BasketTrainerApp.kt` — call `GarminManager.init(this)`

**Interfaces:**
- Consumes: nothing from earlier tasks yet (message reception wiring is Task 6)
- Produces: `GarminManager.init(context: Context)`, `GarminManager.connectWatch()`, `GarminManager.connectedDevice: StateFlow<IQDevice?>`, `GarminManager.garminConnectAvailable: StateFlow<Boolean>`. Task 6 extends this file to add message reception; Task 7's `HomeScreen` consumes `connectedDevice` and `garminConnectAvailable`.

This task requires the real Connect IQ SDK, Garmin Connect Mobile, and a paired watch to observe any actual callback — there is no fake/mock for the SDK, so verification here is a manual, device-based smoke test.

- [ ] **Step 1: Add the Connect IQ SDK dependency**

Modify `android-app/app/build.gradle.kts`, add to `dependencies { ... }`:

```kotlin
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.4.0@aar")
```

This artifact is published on Maven Central (confirmed via the official `garmin/connectiq-android-sdk` repo and its `Comm Android` sample, which pins the same coordinates) — no manual AAR download or extra repository entry is needed, unlike the iOS `.xcframework` step in the root `CLAUDE.md`.

- [ ] **Step 2: Write `GarminManager.kt`**

```kotlin
package com.tonnom.baskettrainer.garmin

import android.content.Context
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

object GarminManager {
    // Doit rester identique à garmin-app/manifest.xml et
    // ios-app/BasketTrainer/Managers/GarminManager.swift.
    const val APP_UUID = "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a"

    private lateinit var connectIQ: ConnectIQ
    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _connectedDevice = MutableStateFlow<IQDevice?>(null)
    val connectedDevice: StateFlow<IQDevice?> get() = _connectedDevice

    private val _garminConnectAvailable = MutableStateFlow(true)
    val garminConnectAvailable: StateFlow<Boolean> get() = _garminConnectAvailable

    private val connectIQListener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            connectWatch()
        }

        override fun onInitializeError(errStatus: ConnectIQ.IQSdkErrorStatus) {
            _garminConnectAvailable.value = false
        }

        override fun onSdkShutDown() {}
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        connectIQ = ConnectIQ.getInstance(appContext, ConnectIQ.IQConnectType.WIRELESS)
        connectIQ.initialize(appContext, true, connectIQListener)
    }

    fun connectWatch() {
        scope.launch {
            val devices = try {
                connectIQ.knownDevices ?: emptyList()
            } catch (e: InvalidStateException) {
                emptyList()
            } catch (e: ServiceUnavailableException) {
                _garminConnectAvailable.value = false
                emptyList()
            }

            devices.forEach { device ->
                connectIQ.unregisterForDeviceEvents(device)
                connectIQ.registerForDeviceEvents(device) { updatedDevice, status ->
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        _connectedDevice.value = updatedDevice
                        registerForAppMessages(updatedDevice)
                    } else if (_connectedDevice.value?.deviceIdentifier == updatedDevice.deviceIdentifier) {
                        _connectedDevice.value = null
                    }
                }
            }
        }
    }

    private fun registerForAppMessages(device: IQDevice) {
        // Extended in Task 6 to parse and store incoming sessions.
    }
}
```

- [ ] **Step 3: Wire it into `BasketTrainerApp`**

Modify `android-app/app/src/main/java/com/tonnom/baskettrainer/BasketTrainerApp.kt`:

```kotlin
package com.tonnom.baskettrainer

import android.app.Application
import com.tonnom.baskettrainer.data.SessionRepository
import com.tonnom.baskettrainer.garmin.GarminManager

class BasketTrainerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SessionRepository.init(this)
        GarminManager.init(this)
    }
}
```

- [ ] **Step 4: Build to confirm it compiles**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: [MANUAL — physical device required] Install and smoke-test SDK init**

Install on the Android phone (with Garmin Connect Mobile already installed and the FR255 paired):

```bash
./gradlew installDebug
```

Launch the app. Expected: no crash. There is nothing to see on screen yet (Task 7 adds the UI) — this step only confirms `ConnectIQ.initialize()` doesn't throw and `onSdkReady()`/`onInitializeError()` fires. Check via `adb logcat` if unsure it ran (temporarily add a `Log.d("GarminManager", ...)` line in the listener if needed, then remove it before committing).

- [ ] **Step 6: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): initialize Connect IQ SDK and connect known devices"
```

---

### Task 6: Message reception (GarminMessageParser + wiring)

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/garmin/GarminMessageParser.kt`
- Create: `android-app/app/src/test/java/com/tonnom/baskettrainer/garmin/GarminMessageParserTest.kt`
- Modify: `android-app/app/src/main/java/com/tonnom/baskettrainer/garmin/GarminManager.kt` — call the parser from `registerForAppMessages` and forward the result to `SessionRepository`

**Interfaces:**
- Consumes: `WorkoutSession`, `ShotSeries`, `ExerciseType`, `ShotType` (Task 2); `SessionRepository.add` (Task 4)
- Produces: `GarminMessageParser.parse(dict: Map<*, *>): WorkoutSession` — a pure function, the Android equivalent of `GarminManager.swift`'s `parseAndStore`. Task 9's end-to-end QA is the only way to confirm the real watch payload shape matches what this function expects.

The watch (`garmin-app/source/WorkoutSession.mc:toDictionary()` and `GoalSession.mc:toDictionary()`) calls `Communications.transmit(dict, ...)` with a single top-level `Dictionary`. On Android, the Connect IQ SDK delivers any `transmit()`ed payload as a `List<Any>` (confirmed against Garmin's own current `Comm Android` sample and forum documentation on the Monkey C ↔ Android type mapping); for a single-Dictionary payload that means a one-element list whose first element is a `Map`. `GarminMessageParser.parse` takes that already-unwrapped `Map` — the unwrapping happens in `GarminManager`.

- [ ] **Step 1: Write the failing tests**

```kotlin
// android-app/app/src/test/java/com/tonnom/baskettrainer/garmin/GarminMessageParserTest.kt
package com.tonnom.baskettrainer.garmin

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.ShotType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GarminMessageParserTest {

    // Matches the keys WorkoutSession.mc#toDictionary() actually sends.
    private fun baseWatchPayload(): Map<String, Any?> = mapOf(
        "exerciseId" to 6,
        "exerciseName" to "Mi-distance Centre",
        "totalShots" to 10,
        "madeShots" to 7,
        "percentage" to 70,
        "startTime" to 1_700_000_000,
        "results" to listOf(true, true, false, true, true, false, true, false, true, true),
        "duration" to 245,
        "shotTypeId" to 1
    )

    @Test
    fun `parses a simple session`() {
        val session = GarminMessageParser.parse(baseWatchPayload())

        assertEquals(ExerciseType.MID_CENTER, session.exerciseType)
        assertEquals(10, session.totalShots)
        assertEquals(7, session.madeShots)
        assertEquals(1_700_000_000_000L, session.date)
        assertEquals(245L, session.duration)
        assertEquals(ShotType.OFF_DRIBBLE, session.shotType)
        assertEquals(true, session.sentFromWatch)
        assertNull(session.series)
    }

    @Test
    fun `a targetMade field produces a single-entry series with that target`() {
        val payload = baseWatchPayload() + mapOf("targetMade" to 8)

        val session = GarminMessageParser.parse(payload)

        assertEquals(1, session.series?.size)
        val series = session.series!!.first()
        assertEquals(ExerciseType.MID_CENTER, series.exerciseType)
        assertEquals(8, series.targetMade)
        assertEquals(10, series.totalShots)
        assertEquals(7, series.madeShots)
    }

    @Test
    fun `missing optional fields fall back to safe defaults`() {
        val session = GarminMessageParser.parse(mapOf("exerciseId" to 0))

        assertEquals(ExerciseType.FREETHROW, session.exerciseType)
        assertEquals(0, session.totalShots)
        assertEquals(0, session.madeShots)
        assertEquals(emptyList<Boolean>(), session.results)
        assertNull(session.shotType)
        assertNull(session.duration)
        assertNull(session.series)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.garmin.GarminMessageParserTest"
```

Expected: FAIL — `GarminMessageParser` does not exist yet.

- [ ] **Step 3: Write `GarminMessageParser.kt`**

```kotlin
package com.tonnom.baskettrainer.garmin

import com.tonnom.baskettrainer.model.ExerciseType
import com.tonnom.baskettrainer.model.ShotSeries
import com.tonnom.baskettrainer.model.ShotType
import com.tonnom.baskettrainer.model.WorkoutSession

object GarminMessageParser {

    fun parse(dict: Map<*, *>): WorkoutSession {
        val exerciseId = (dict["exerciseId"] as? Number)?.toInt() ?: 0
        val exerciseType = ExerciseType.fromId(exerciseId)
        val totalShots = (dict["totalShots"] as? Number)?.toInt() ?: 0
        val madeShots = (dict["madeShots"] as? Number)?.toInt() ?: 0
        val startTime = (dict["startTime"] as? Number)?.toLong() ?: 0L
        val duration = (dict["duration"] as? Number)?.toLong()
        @Suppress("UNCHECKED_CAST")
        val results = (dict["results"] as? List<Boolean>) ?: emptyList()
        val targetMade = (dict["targetMade"] as? Number)?.toInt()
        val shotType = (dict["shotTypeId"] as? Number)?.toInt()?.let { ShotType.fromId(it) }

        val series = targetMade?.let {
            listOf(
                ShotSeries(
                    exerciseType = exerciseType,
                    totalShots = totalShots,
                    madeShots = madeShots,
                    results = results,
                    targetMade = it,
                    shotType = shotType
                )
            )
        }

        return WorkoutSession(
            exerciseType = exerciseType,
            totalShots = totalShots,
            madeShots = madeShots,
            results = results,
            date = startTime * 1000,
            sentFromWatch = true,
            series = series,
            duration = duration,
            shotType = shotType
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew :app:testDebugUnitTest --tests "com.tonnom.baskettrainer.garmin.GarminMessageParserTest"
```

Expected: PASS, all 3 tests green.

- [ ] **Step 5: Wire the parser into `GarminManager`**

Modify `android-app/app/src/main/java/com/tonnom/baskettrainer/garmin/GarminManager.kt`. Add two new imports alongside the existing ones from Task 5 (`ConnectIQ`, `IQDevice`, `InvalidStateException`, `ServiceUnavailableException` are already there — don't duplicate them):

```kotlin
import com.garmin.android.connectiq.IQApp
import com.tonnom.baskettrainer.data.SessionRepository
```

Then replace the empty `registerForAppMessages` body:

```kotlin
    private fun registerForAppMessages(device: IQDevice) {
        try {
            connectIQ.registerForAppEvents(device, IQApp(APP_UUID)) { _, _, message, status ->
                if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                    val dict = message.firstOrNull() as? Map<*, *> ?: return@registerForAppEvents
                    SessionRepository.add(GarminMessageParser.parse(dict))
                }
            }
        } catch (e: InvalidStateException) {
            _garminConnectAvailable.value = false
        } catch (e: ServiceUnavailableException) {
            _garminConnectAvailable.value = false
        }
    }
```

- [ ] **Step 6: Build to confirm it compiles**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): parse and store sessions received from the watch"
```

---

### Task 7: HomeScreen

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/ui/theme/Color.kt`
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/ui/theme/Theme.kt`
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/ui/components/SessionRow.kt`
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/ui/HomeScreen.kt`

**Interfaces:**
- Consumes: `SessionRepository.sessions/totalSessions/totalShots/overallPercentage` (Task 4), `GarminManager.connectedDevice/garminConnectAvailable/connectWatch()` (Task 5)
- Produces: `@Composable fun HomeScreen()`, `@Composable fun SessionRow(session: WorkoutSession)`. Task 8 places `HomeScreen` as one of the two bottom-nav destinations.

No automated test — this is Compose UI. Verification is manual (Step 5).

- [ ] **Step 1: Write the dark theme + orange accent**

```kotlin
// android-app/app/src/main/java/com/tonnom/baskettrainer/ui/theme/Color.kt
package com.tonnom.baskettrainer.ui.theme

import androidx.compose.ui.graphics.Color

val AccentOrange = Color(0xFFFF6600)
val BackgroundDark = Color(0xFF121212)
val SurfaceDark = Color(0xFF1E1E1E)
val OnSurfaceDark = Color(0xFFEDEDED)
```

```kotlin
// android-app/app/src/main/java/com/tonnom/baskettrainer/ui/theme/Theme.kt
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
```

- [ ] **Step 2: Write `SessionRow`**

```kotlin
// android-app/app/src/main/java/com/tonnom/baskettrainer/ui/components/SessionRow.kt
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
```

- [ ] **Step 3: Write `HomeScreen`**

```kotlin
// android-app/app/src/main/java/com/tonnom/baskettrainer/ui/HomeScreen.kt
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
```

- [ ] **Step 4: Build to confirm it compiles**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: [MANUAL — physical device or emulator] Wire it into `MainActivity` temporarily to eyeball it**

This is a throwaway check, not the final wiring (Task 8 does that properly with navigation). Temporarily replace the `setContent` body in `MainActivity.kt` with:

```kotlin
        setContent {
            com.tonnom.baskettrainer.ui.theme.BasketTrainerTheme {
                com.tonnom.baskettrainer.ui.HomeScreen()
            }
        }
```

Run `./gradlew installDebug`, launch the app, confirm: watch status row, three stat cards (all zero on first launch), "Récentes" header, empty list. Revert this temporary change before committing — Task 8 replaces `MainActivity` properly.

- [ ] **Step 6: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): add HomeScreen with watch status and quick stats"
```

---

### Task 8: HistoryScreen + navigation

**Files:**
- Create: `android-app/app/src/main/java/com/tonnom/baskettrainer/ui/HistoryScreen.kt`
- Modify: `android-app/app/src/main/java/com/tonnom/baskettrainer/MainActivity.kt` — replace the placeholder content with a bottom-nav `NavHost`
- Modify: `android-app/app/build.gradle.kts` — add Navigation Compose

**Interfaces:**
- Consumes: `SessionRepository.sessions/delete` (Task 4), `SessionRow` (Task 7), `HomeScreen` (Task 7)
- Produces: `@Composable fun HistoryScreen()`. Nothing later in this plan depends on it — this is the last screen in scope.

No automated test — this is Compose UI + navigation glue. Verification is manual (Step 5).

- [ ] **Step 1: Add Navigation Compose and the extended icon set**

Modify `android-app/app/build.gradle.kts`, add to `dependencies { ... }`:

```kotlin
    implementation("androidx.navigation:navigation-compose:2.8.4")
    // Icons.Default.Delete/Home are in the core icon set bundled with material3,
    // but Icons.Default.History (used below and in MainActivity) is not — pull
    // in the extended set so both resolve.
    implementation("androidx.compose.material:material-icons-extended:1.7.5")
```

- [ ] **Step 2: Write `HistoryScreen`**

```kotlin
// android-app/app/src/main/java/com/tonnom/baskettrainer/ui/HistoryScreen.kt
package com.tonnom.baskettrainer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
    Row(verticalAlignment = Alignment.CenterVertically) {
        SessionRow(session, modifier = Modifier.weight(1f))
        IconButton(onClick = onDelete) {
            Icon(Icons.Default.Delete, contentDescription = "Supprimer")
        }
    }
}

private fun dayLabel(epochMillis: Long): String =
    SimpleDateFormat("EEEE d MMMM", Locale.FRANCE).format(Date(epochMillis))
        .replaceFirstChar { it.uppercase() }
```

- [ ] **Step 3: Rewire `MainActivity` with bottom navigation**

Replace the contents of `android-app/app/src/main/java/com/tonnom/baskettrainer/MainActivity.kt`:

```kotlin
package com.tonnom.baskettrainer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.tonnom.baskettrainer.ui.HistoryScreen
import com.tonnom.baskettrainer.ui.HomeScreen
import com.tonnom.baskettrainer.ui.theme.BasketTrainerTheme

private enum class Tab(val route: String, val label: String) {
    HOME("home", "Accueil"),
    HISTORY("history", "Historique")
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BasketTrainerTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MainScaffold()
                }
            }
        }
    }
}

@Composable
private fun MainScaffold() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                val backStackEntry by navController.currentBackStackEntryAsState()
                val currentRoute = backStackEntry?.destination

                Tab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute?.hierarchy?.any { it.route == tab.route } == true,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Icon(
                                if (tab == Tab.HOME) Icons.Default.Home else Icons.Default.History,
                                contentDescription = tab.label
                            )
                        },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Tab.HOME.route,
            modifier = Modifier.padding(padding)
        ) {
            composable(Tab.HOME.route) { HomeScreen() }
            composable(Tab.HISTORY.route) { HistoryScreen() }
        }
    }
}
```

- [ ] **Step 4: Build to confirm it compiles**

```bash
cd /Users/manu/Documents/GitHub/App-garmin/android-app
./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: [MANUAL — physical device or emulator]**

```bash
./gradlew installDebug
```

Launch the app. Confirm: bottom bar with Accueil/Historique tabs, tapping switches screens and preserves each screen's scroll position (`saveState`/`restoreState`), Historique shows "Aucune séance pour l'instant." on first launch.

- [ ] **Step 6: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add android-app
git commit -m "feat(android): add HistoryScreen and bottom-nav between Accueil/Historique"
```

---

### Task 9: End-to-end verification with the real watch

**Files:** none — this task wires nothing new, it validates Tasks 1-8 together.

- [ ] **Step 1: [MANUAL — physical device required] Full flow**

1. Confirm Garmin Connect Mobile is installed on the Android phone and the Forerunner 255 is paired to it.
2. `cd /Users/manu/Documents/GitHub/App-garmin/android-app && ./gradlew installDebug`
3. Launch Basket Trainer on the phone. On the Accueil tab, tap "Connecter" if the watch doesn't auto-connect.
4. On the watch, start a shooting session (any exercise, e.g. Lancer Franc) and record a handful of makes/misses, then finish it so `SummaryView.mc` transmits.
5. Confirm the phone shows "Montre connectée" and the new session appears at the top of Accueil's "Récentes" list and in Historique, with the correct exercise name, made/total, and percentage matching what was shown on the watch.
6. Force-close and relaunch the app. Confirm the session is still there (validates `SessionRepository` persistence end-to-end, which Task 4 could not verify without a device).
7. Swipe/tap delete on that session in Historique, confirm it disappears and stays gone after relaunch.

If step 5 shows no session arriving: check `adb logcat` for `InvalidStateException`/`ServiceUnavailableException` from `GarminManager`, and re-verify the `IQApp(APP_UUID)` string format against the actual behavior — Garmin's own sample app uses a 32-character hex id with no dashes (`"a3421feed289106a538cb9547ab12095"`) where this plan uses the standard dashed UUID form (`"a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a"`, matching `manifest.xml` and the iOS app). If messages aren't received, try stripping the dashes in `GarminManager.APP_UUID` as the first troubleshooting step.

- [ ] **Step 2: Update `CLAUDE.md`**

Add an "Android" section to the root `CLAUDE.md` (mirroring the existing Garmin/iPhone sections) once the flow above is confirmed working, documenting: the `android-app/` structure, `./gradlew installDebug` as the run command, and the same UUID note already present for iOS.

- [ ] **Step 3: Commit**

```bash
cd /Users/manu/Documents/GitHub/App-garmin
git add CLAUDE.md
git commit -m "docs: document Android app in CLAUDE.md"
```
