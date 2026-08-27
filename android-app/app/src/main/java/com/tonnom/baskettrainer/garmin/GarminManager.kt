package com.tonnom.baskettrainer.garmin

import android.content.Context
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import com.tonnom.baskettrainer.data.SessionRepository
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

    private val appMessageRegisteredDevices = mutableSetOf<Long>()

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

            try {
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
                    // Le SDK ne rejoue pas forcément le callback ci-dessus pour un
                    // appareil déjà connecté au lancement de l'app : on initialise
                    // aussi l'état à partir du statut courant.
                    if (connectIQ.getDeviceStatus(device) == IQDevice.IQDeviceStatus.CONNECTED) {
                        _connectedDevice.value = device
                        registerForAppMessages(device)
                    }
                }
            } catch (e: InvalidStateException) {
                _garminConnectAvailable.value = false
            } catch (e: ServiceUnavailableException) {
                _garminConnectAvailable.value = false
            }
        }
    }

    private fun registerForAppMessages(device: IQDevice) {
        if (!appMessageRegisteredDevices.add(device.deviceIdentifier)) return
        try {
            val app = IQApp(APP_UUID)
            connectIQ.registerForAppEvents(device, app) { _, _, message, status ->
                if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                    val dict = message.firstOrNull() as? Map<*, *> ?: return@registerForAppEvents
                    SessionRepository.add(GarminMessageParser.parse(dict))
                }
            }
            // Réveille l'app montre → BasketApp.onStart() → SyncManager flush de la
            // PendingQueue (sessions accumulées hors portée / app iPhone fermée).
            connectIQ.openApplication(device, app) { _, _, _ -> }
        } catch (e: InvalidStateException) {
            _garminConnectAvailable.value = false
        } catch (e: ServiceUnavailableException) {
            _garminConnectAvailable.value = false
        }
    }
}
